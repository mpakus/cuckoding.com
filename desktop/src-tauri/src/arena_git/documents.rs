//! Bounded docs-first snapshots. No Git, project configuration or provider access.
use super::*;
use std::{
    collections::BTreeMap,
    ffi::{CStr, CString},
    os::fd::IntoRawFd,
};

const POLICY: &str = "folder-documents-v1";
const ENTRY_LIMIT: usize = 2_000;
const FILE_LIMIT: usize = 16;
const BYTE_LIMIT: usize = 65_536;

fn allowed_path(path: &str) -> bool {
    initial::paths(&json!([path])).is_ok()
        && path.split('/').all(|part| {
            let part = part.to_ascii_lowercase();
            !part.starts_with('.')
                && !["secret", "credential", "token"]
                    .iter()
                    .any(|p| part.starts_with(p))
                && ![
                    "node_modules",
                    "deps",
                    "_build",
                    "target",
                    "build",
                    "dist",
                    "vendor",
                    "coverage",
                    "venv",
                    "__pycache__",
                ]
                .contains(&part.as_str())
        })
}

fn eligible(path: &str) -> bool {
    allowed_path(path)
        && Path::new(path)
            .extension()
            .and_then(|s| s.to_str())
            .is_some_and(|s| {
                [
                    "md", "txt", "ex", "exs", "rs", "js", "jsx", "ts", "tsx", "py", "rb", "go",
                    "swift", "java", "kt", "c", "h", "cpp", "hpp", "css", "html", "heex", "sql",
                    "json", "toml", "yaml", "yml",
                ]
                .contains(&s.to_ascii_lowercase().as_str())
            })
}

pub(crate) fn valid_files(value: &Value) -> bool {
    let Some(files) = value.as_array() else {
        return false;
    };
    let paths = json!(files.iter().map(|f| &f["path"]).collect::<Vec<_>>());
    files.len() <= FILE_LIMIT
        && initial::paths(&paths).is_ok()
        && files.iter().all(|f| {
            f.as_object().is_some_and(|m| m.len() == 4)
                && f["path"].as_str().is_some_and(eligible)
                && f["text"].as_str().is_some_and(|text| {
                    text.len() <= 16_384
                        && !text
                            .chars()
                            .any(|c| c.is_control() && !['\n', '\r', '\t'].contains(&c))
                        && f["bytes"].as_u64() == Some(text.len() as u64)
                        && f["sha256"] == initial::digest(text.as_bytes())
                })
        })
        && files
            .iter()
            .map(|f| f["bytes"].as_u64().unwrap_or(BYTE_LIMIT as u64 + 1))
            .sum::<u64>()
            <= BYTE_LIMIT as u64
}

struct Entries(*mut libc::DIR);
impl Drop for Entries {
    fn drop(&mut self) {
        unsafe {
            libc::closedir(self.0);
        }
    }
}

#[derive(Default)]
struct Scan {
    files: Vec<Value>,
    visited: usize,
    bytes: usize,
    skipped: BTreeMap<&'static str, usize>,
    limited: bool,
}

impl Scan {
    fn skip(&mut self, reason: &'static str) {
        *self.skipped.entry(reason).or_default() += 1;
    }

    fn names(&mut self, git: &Git<'_>, directory: &File) -> Result<Vec<String>> {
        // Open a new stream relative to the pinned descriptor, never a reconstructed path.
        let fd =
            initial::open_at(directory, ".", libc::O_RDONLY | libc::O_DIRECTORY)?.into_raw_fd();
        let stream = unsafe { libc::fdopendir(fd) };
        if stream.is_null() {
            unsafe {
                libc::close(fd);
            }
            return Err("unsafe_file");
        }
        let stream = Entries(stream);
        let mut names = Vec::new();
        loop {
            git.active()?;
            if self.visited == ENTRY_LIMIT {
                self.limited = true;
                break;
            }
            unsafe {
                *libc::__error() = 0;
            }
            let entry = unsafe { libc::readdir(stream.0) };
            if entry.is_null() {
                if std::io::Error::last_os_error().raw_os_error() != Some(0) {
                    return Err("unsafe_file");
                }
                break;
            }
            let name = unsafe { CStr::from_ptr((*entry).d_name.as_ptr()) };
            if name.to_bytes() == b"." || name.to_bytes() == b".." {
                continue;
            }
            self.visited += 1;
            match name.to_str() {
                Ok(name) => names.push(name.to_owned()),
                Err(_) => self.skip("excluded"),
            }
        }
        names.sort_by_key(|name| (name != "docs", name.clone()));
        Ok(names)
    }

    fn walk(&mut self, git: &Git<'_>, directory: &File, prefix: &str, depth: usize) -> Result<()> {
        for name in self.names(git, directory)? {
            git.active()?;
            let path = if prefix.is_empty() {
                name.clone()
            } else {
                format!("{prefix}/{name}")
            };
            if !allowed_path(&path) {
                self.skip("excluded");
                continue;
            }
            let c_name = CString::new(name.as_str()).map_err(|_| "invalid_selection")?;
            let mut stat: libc::stat = unsafe { std::mem::zeroed() };
            if unsafe {
                libc::fstatat(
                    directory.as_raw_fd(),
                    c_name.as_ptr(),
                    &mut stat,
                    libc::AT_SYMLINK_NOFOLLOW,
                )
            } != 0
            {
                self.skip("unreadable");
                continue;
            }
            match stat.st_mode & libc::S_IFMT {
                libc::S_IFDIR => {
                    if depth >= 6 || self.visited == ENTRY_LIMIT {
                        self.limited = true;
                        self.skip("limit");
                        continue;
                    }
                    match initial::open_at(directory, &name, libc::O_RDONLY | libc::O_DIRECTORY) {
                        Ok(child) => self.walk(git, &child, &path, depth + 1)?,
                        Err(_) => self.skip("unsafe"),
                    }
                }
                libc::S_IFREG if stat.st_nlink == 1 => {
                    if !eligible(&path) {
                        self.skip("unsupported");
                        continue;
                    }
                    if self.files.len() == FILE_LIMIT
                        || stat.st_size < 0
                        || stat.st_size > 16_384
                        || self.bytes + stat.st_size as usize > BYTE_LIMIT
                    {
                        self.limited = true;
                        self.skip("limit");
                        continue;
                    }
                    self.read(directory, &name, &path)?;
                }
                _ => self.skip("unsafe"),
            }
        }
        Ok(())
    }

    fn read(&mut self, directory: &File, name: &str, path: &str) -> Result<()> {
        let (mut file, bytes) = match initial::read_at(
            directory,
            name,
            (BYTE_LIMIT - self.bytes).min(16_384) as u64,
        ) {
            Ok(value) => value,
            Err("preview_changed") => return Err("preview_changed"),
            Err("selection_limit") => {
                self.limited = true;
                self.skip("limit");
                return Ok(());
            }
            Err(_) => {
                self.skip("unreadable");
                return Ok(());
            }
        };
        if self.bytes + bytes.len() > BYTE_LIMIT {
            self.limited = true;
            self.skip("limit");
            return Ok(());
        }
        self.bytes += bytes.len();
        let Ok(text) = String::from_utf8(bytes) else {
            self.skip("invalid_text");
            return Ok(());
        };
        if text
            .chars()
            .any(|c| c.is_control() && !['\n', '\r', '\t'].contains(&c))
        {
            self.skip("invalid_text");
            return Ok(());
        }
        file.as_object_mut().unwrap().remove("mode");
        file["path"] = json!(path);
        file["text"] = json!(text);
        self.files.push(file);
        Ok(())
    }
}

pub(super) fn scan(git: &Git<'_>, extra: &str) -> Result<Value> {
    if serde_json::from_str::<Value>(extra).ok() != Some(json!({"policy":POLICY})) {
        return Err("invalid_selection");
    }
    let mut scan = Scan::default();
    scan.walk(git, &git.directory, "", 0)?;
    git.active()?;
    let files = json!(scan.files);
    if !valid_files(&files) {
        return Err("invalid_text");
    }
    Ok(json!({"status":"previewed", "policy":POLICY, "files":files,
        "scan":{"visited":scan.visited,"skipped":scan.skipped,"limited":scan.limited}}))
}
