//! Conservative raw-byte observation; never trust index flags as proof of unchanged files.
use super::*;
use std::{collections::BTreeSet, ffi::CStr, path::PathBuf};

struct Owned {
    checkout: File,
    admin: File,
    index: PathBuf,
}

fn read(directory: &File, path: &str, limit: u64) -> Result<Vec<u8>> {
    initial::read_at(directory, path, limit)
        .map(|(_, bytes)| bytes)
        .map_err(|_| "worktree_mismatch")
}

fn owned(git: &Git<'_>, request: &Value, device: u64, inode: u64) -> Result<Owned> {
    let key = initial::uuid(&request["key"])?;
    let parent = git.home.join("worktrees").join(key);
    private_directory(&git.home.join("worktrees")).map_err(|_| "worktree_mismatch")?;
    private_directory(&parent).map_err(|_| "worktree_mismatch")?;
    let checkout = parent.join("checkout");
    if request["path"].as_str() != checkout.to_str() {
        return Err("worktree_mismatch");
    }
    let owner = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_DIRECTORY)
        .open(&parent)
        .map_err(|_| "worktree_mismatch")?;
    let expected = json!({"version":1,"key":key,"head":request["head"],
        "source_device":device,"source_inode":inode,"path":checkout});
    let marker: Value = serde_json::from_slice(&read(&owner, "owner.json", 8192)?)
        .map_err(|_| "worktree_mismatch")?;
    if marker != expected {
        return Err("worktree_mismatch");
    }
    let directory = initial::open_at(&owner, "checkout", libc::O_RDONLY | libc::O_DIRECTORY)
        .map_err(|_| "worktree_mismatch")?;
    let metadata = directory.metadata().map_err(|_| "worktree_mismatch")?;
    if request["device"].as_u64() != Some(metadata.dev())
        || request["inode"].as_u64() != Some(metadata.ino())
        || checkout.canonicalize().ok().as_deref() != Some(&checkout)
    {
        return Err("worktree_mismatch");
    }
    // Treat the checkout pointer only as a candidate within this source's worktrees directory.
    let pointer = read(&directory, ".git", 8192)?;
    let pointer = std::str::from_utf8(&pointer).map_err(|_| "worktree_mismatch")?;
    let path = pointer
        .strip_prefix("gitdir: ")
        .and_then(|p| p.strip_suffix('\n'))
        .ok_or("worktree_mismatch")?;
    let admin_path = Path::new(path);
    let container = git.root.join(".git/worktrees");
    if admin_path.parent() != Some(container.as_path()) {
        return Err("worktree_mismatch");
    }
    let name = admin_path
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or("worktree_mismatch")?;
    if name.is_empty() || name == "." || name == ".." || name.chars().any(char::is_control) {
        return Err("worktree_mismatch");
    }
    let mut admin = git.directory.try_clone().map_err(|_| "worktree_mismatch")?;
    for part in [".git", "worktrees", name] {
        admin = initial::open_at(&admin, part, libc::O_RDONLY | libc::O_DIRECTORY)
            .map_err(|_| "worktree_mismatch")?;
    }
    let head = request["head"].as_str().ok_or("invalid_request")?;
    if read(&admin, "commondir", 8192)? != b"../..\n"
        || read(&admin, "gitdir", 8192)? != format!("{}/.git\n", checkout.display()).as_bytes()
        || read(&admin, "locked", 256)? != format!("{key}\n").as_bytes()
        || read(&admin, "HEAD", 256)? != format!("{head}\n").as_bytes()
    {
        return Err("worktree_mismatch");
    }
    Ok(Owned {
        checkout: directory,
        admin,
        index: admin_path.join("index"),
    })
}

fn index_matches(git: &Git<'_>, owned: &Owned, entries: &[Entry]) -> Result<bool> {
    let (code, bytes) = git.command_bounded(
        &["ls-files", "--stage", "-z"],
        true,
        None,
        Some(&owned.index),
        TREE_LIMIT,
    )?;
    if code != 0 {
        return Err("worktree_mismatch");
    }
    let actual: BTreeSet<_> = bytes.split(|b| *b == 0).filter(|b| !b.is_empty()).collect();
    let expected: Vec<_> = entries
        .iter()
        .map(|e| format!("{} {} 0\t{}", e.mode, e.oid, e.path))
        .collect();
    Ok(actual == expected.iter().map(|s| s.as_bytes()).collect())
}

// fdopendir owns only this duplicate; all descendant opens remain descriptor-relative.
struct Directory(*mut libc::DIR);
impl Drop for Directory {
    fn drop(&mut self) {
        unsafe {
            libc::closedir(self.0);
        }
    }
}

fn extra_files(git: &Git<'_>, root: &File, entries: &[Entry]) -> Result<bool> {
    let files: BTreeSet<_> = entries.iter().map(|e| e.path.as_str()).collect();
    let mut directories = BTreeSet::new();
    for entry in entries {
        for (index, _) in entry.path.match_indices('/') {
            directories.insert(&entry.path[..index]);
        }
    }
    let mut pending = vec![(
        root.try_clone().map_err(|_| "worktree_mismatch")?,
        String::new(),
    )];
    let mut count = 0;
    while let Some((directory, prefix)) = pending.pop() {
        let fd = unsafe { libc::dup(directory.as_raw_fd()) };
        if fd < 0 {
            return Err("worktree_mismatch");
        }
        let stream = unsafe { libc::fdopendir(fd) };
        if stream.is_null() {
            unsafe {
                libc::close(fd);
            }
            return Err("worktree_mismatch");
        }
        let stream = Directory(stream);
        loop {
            git.active()?;
            // macOS errno distinguishes end-of-directory from a failed read.
            unsafe {
                *libc::__error() = 0;
            }
            let entry = unsafe { libc::readdir(stream.0) };
            if entry.is_null() {
                if unsafe { *libc::__error() } != 0 {
                    return Err("worktree_mismatch");
                }
                break;
            }
            let name = unsafe { CStr::from_ptr((*entry).d_name.as_ptr()) };
            let Ok(name) = name.to_str() else {
                return Ok(true);
            };
            if [".", ".."].contains(&name) || (prefix.is_empty() && name == ".git") {
                continue;
            }
            count += 1;
            if count > 20_000 {
                return Err("tree_limit");
            }
            let path = format!("{prefix}{name}");
            if directories.contains(path.as_str()) {
                let Ok(child) =
                    initial::open_at(&directory, name, libc::O_RDONLY | libc::O_DIRECTORY)
                else {
                    return Ok(true);
                };
                pending.push((child, format!("{path}/")));
            } else if !files.contains(path.as_str()) {
                return Ok(true);
            }
        }
    }
    Ok(false)
}

fn files_match(git: &Git<'_>, owned: &Owned, entries: &[Entry]) -> Result<bool> {
    let input = entries
        .iter()
        .map(|e| format!("{}\n", e.oid))
        .collect::<String>();
    let (code, bytes) = git.command_bounded(
        &["cat-file", "--batch"],
        true,
        Some(input.into_bytes()),
        None,
        68_157_440,
    )?;
    if code != 0 {
        return Err("invalid_repository");
    }
    let mut remaining = bytes.as_slice();
    for entry in entries {
        git.active()?;
        let header = format!("{} blob {}\n", entry.oid, entry.bytes);
        remaining = remaining
            .strip_prefix(header.as_bytes())
            .ok_or("invalid_repository")?;
        if remaining.len() <= entry.bytes || remaining[entry.bytes] != b'\n' {
            return Err("invalid_repository");
        }
        let Ok((metadata, content)) = initial::read_at(&owned.checkout, &entry.path, 8_388_608)
        else {
            return Ok(false);
        };
        if content != remaining[..entry.bytes] || metadata["mode"] != entry.mode {
            return Ok(false);
        }
        remaining = &remaining[entry.bytes + 1..];
    }
    if !remaining.is_empty() {
        return Err("invalid_repository");
    }
    Ok(!extra_files(git, &owned.checkout, entries)?)
}

pub(in super::super) fn inspect(
    git: &Git<'_>,
    extra: &str,
    device: u64,
    inode: u64,
) -> Result<Value> {
    if extra.len() > 8192 {
        return Err("invalid_request");
    }
    let mut request: Value = serde_json::from_str(extra).map_err(|_| "invalid_request")?;
    let head = request["head"].as_str().ok_or("invalid_request")?;
    if head.len() != 40 || !head.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err("invalid_request");
    }
    git.inspect()?;
    let config = configuration(git)?;
    let owned = owned(git, &request, device, inode)?;
    let index = read(&owned.admin, "index", 8_388_608)?;
    let entries = tree(git, head)?;
    let unchanged = index_matches(git, &owned, &entries)? && files_match(git, &owned, &entries)?;
    git.identity(device, inode)?;
    let current = self::owned(git, &request, device, inode)?;
    if read(&current.admin, "index", 8_388_608)? != index || configuration(git)? != config {
        return Err("worktree_mismatch");
    }
    git.active()?;
    request["status"] = json!(if unchanged {
        "worktree_unchanged"
    } else {
        "worktree_changed"
    });
    Ok(request)
}
