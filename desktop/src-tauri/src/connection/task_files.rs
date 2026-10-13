//! Closed descriptor-relative tools. No shell, Git, permissions or credential operations.
use super::*;
use sha2::{Digest, Sha256};
use std::{
    ffi::{CStr, CString},
    fs,
    os::{
        fd::{FromRawFd, IntoRawFd},
        unix::fs::MetadataExt,
    },
    path::PathBuf,
};

const FILE_BYTES: usize = 32_768;
const TOTAL_BYTES: usize = 524_288;

pub(super) fn digest(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

pub(crate) fn valid_path(path: &str, empty: bool) -> bool {
    (empty && path.is_empty())
        || (!path.is_empty()
            && path.len() <= 240
            && path.split('/').count() <= 8
            && path.split('/').all(|part| {
                let lower = part.to_ascii_lowercase();
                !part.is_empty()
                    && !part.starts_with('.')
                    && part
                        .bytes()
                        .all(|b| b.is_ascii_alphanumeric() || b"_-.".contains(&b))
                    && ![
                        "agents.md",
                        "claude.md",
                        "node_modules",
                        "deps",
                        "_build",
                        "target",
                        "vendor",
                        "build",
                        "dist",
                    ]
                    .contains(&lower.as_str())
                    && !["secret", "credential", "token", "id_rsa", "id_ed25519"]
                        .iter()
                        .any(|p| lower.starts_with(p))
                    && !["pem", "key", "p12", "pfx"]
                        .contains(&lower.rsplit('.').next().unwrap_or(""))
            }))
}

fn open_at(directory: &File, name: &str, flags: i32) -> Result<File> {
    let name = CString::new(name).map_err(|_| "invalid_tool")?;
    let fd = unsafe {
        libc::openat(
            directory.as_raw_fd(),
            name.as_ptr(),
            flags | libc::O_NOFOLLOW | libc::O_CLOEXEC | libc::O_NONBLOCK,
            0o600,
        )
    };
    if fd < 0 {
        Err("unsafe_file")
    } else {
        Ok(unsafe { File::from_raw_fd(fd) })
    }
}

fn text(bytes: &[u8]) -> Result<&str> {
    std::str::from_utf8(bytes)
        .ok()
        .filter(|s| {
            !s.chars()
                .any(|c| c.is_control() && !['\n', '\r', '\t'].contains(&c))
        })
        .ok_or("unsupported_file")
}

fn read(directory: &File, name: &str) -> Result<Option<(fs::Metadata, Vec<u8>)>> {
    let file = match open_at(directory, name, libc::O_RDONLY) {
        Ok(file) => file,
        Err(_) if io::Error::last_os_error().raw_os_error() == Some(libc::ENOENT) => {
            return Ok(None)
        }
        Err(error) => return Err(error),
    };
    let before = file.metadata().map_err(|_| "unsafe_file")?;
    if !before.is_file() || before.nlink() != 1 || before.len() > FILE_BYTES as u64 {
        return Err("unsupported_file");
    }
    let mut bytes = Vec::new();
    (&file)
        .take((FILE_BYTES + 1) as u64)
        .read_to_end(&mut bytes)
        .map_err(|_| "unsafe_file")?;
    let after = file.metadata().map_err(|_| "unsafe_file")?;
    if bytes.len() > FILE_BYTES
        || before.len() != bytes.len() as u64
        || before.ctime() != after.ctime()
        || before.ctime_nsec() != after.ctime_nsec()
    {
        return Err("file_changed");
    }
    text(&bytes)?;
    Ok(Some((before, bytes)))
}

pub(super) struct Files {
    root: File,
    path: PathBuf,
    device: u64,
    inode: u64,
    writing: bool,
    journal: File,
    calls: HashSet<String>,
    bytes: usize,
    pub receipts: Vec<Value>,
}

impl Files {
    pub fn new(profile: &Path, scratch: &Path, request: &Value) -> Result<Self> {
        let root = profile
            .parent()
            .filter(|p| p.file_name().is_some_and(|n| n == "agents"))
            .and_then(Path::parent)
            .ok_or("unsafe_workspace")?;
        let workspace = &request["workspace"];
        let key = workspace["key"]
            .as_str()
            .filter(|s| {
                s.len() == 36
                    && s.bytes().enumerate().all(|(i, b)| {
                        if [8, 13, 18, 23].contains(&i) {
                            b == b'-'
                        } else {
                            b.is_ascii_hexdigit()
                        }
                    })
            })
            .ok_or("unsafe_workspace")?;
        let owned = root.join("runtime-home/worktrees").join(key);
        let path = owned.join("checkout");
        private_directory(&owned).map_err(|_| "unsafe_workspace")?;
        if workspace["path"].as_str() != path.to_str()
            || path.canonicalize().ok().as_ref() != Some(&path)
        {
            return Err("unsafe_workspace");
        }
        let parent = File::open(&owned).map_err(|_| "unsafe_workspace")?;
        let marker = read(&parent, "owner.json")?.ok_or("unsafe_workspace")?.1;
        let marker: Value = serde_json::from_slice(&marker).map_err(|_| "unsafe_workspace")?;
        if marker
            != json!({"version":1,"key":key,"head":workspace["head"],"source_device":workspace["source_device"],"source_inode":workspace["source_inode"],"path":path})
        {
            return Err("unsafe_workspace");
        }
        let directory = open_at(&parent, "checkout", libc::O_RDONLY | libc::O_DIRECTORY)?;
        let metadata = directory.metadata().map_err(|_| "unsafe_workspace")?;
        if workspace["device"].as_u64() != Some(metadata.dev())
            || workspace["inode"].as_u64() != Some(metadata.ino())
        {
            return Err("unsafe_workspace");
        }
        let journal = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW)
            .open(scratch.join("tool-receipts.jsonl"))
            .map_err(|_| "attempt_exists")?;
        Ok(Self {
            root: directory,
            path,
            device: metadata.dev(),
            inode: metadata.ino(),
            writing: request["access"] == "write",
            journal,
            calls: HashSet::new(),
            bytes: 0,
            receipts: Vec::new(),
        })
    }

    fn current(&self) -> Result<()> {
        let metadata = fs::symlink_metadata(&self.path).map_err(|_| "unsafe_workspace")?;
        if !metadata.is_dir()
            || metadata.dev() != self.device
            || metadata.ino() != self.inode
            || self.path.canonicalize().ok().as_ref() != Some(&self.path)
        {
            Err("unsafe_workspace")
        } else {
            Ok(())
        }
    }

    fn directory(&self, path: &str, create: bool) -> Result<File> {
        let mut directory = self.root.try_clone().map_err(|_| "unsafe_workspace")?;
        for part in path.split('/').filter(|s| !s.is_empty()) {
            if create {
                let name = CString::new(part).map_err(|_| "invalid_tool")?;
                let result = unsafe { libc::mkdirat(directory.as_raw_fd(), name.as_ptr(), 0o700) };
                if result != 0 && io::Error::last_os_error().raw_os_error() != Some(libc::EEXIST) {
                    return Err("unsafe_file");
                }
            }
            directory = open_at(&directory, part, libc::O_RDONLY | libc::O_DIRECTORY)?;
        }
        Ok(directory)
    }

    fn record(&mut self, entry: Value) -> Result<()> {
        writeln!(self.journal, "{entry}")
            .and_then(|_| self.journal.sync_all())
            .map_err(|_| "journal_failed")
    }

    pub fn call(&mut self, id: &str, tool: &str, args: &Value) -> Result<Value> {
        self.current()?;
        if self.calls.len() >= 64 || !self.calls.insert(id.to_owned()) {
            return Err("tool_limit");
        }
        let path = args["path"]
            .as_str()
            .filter(|p| valid_path(p, tool == "list_files"))
            .ok_or("invalid_tool")?;
        let fields = if tool == "edit_file" { 3 } else { 1 };
        if !args.as_object().is_some_and(|a| a.len() == fields)
            || !["list_files", "read_file", "edit_file"].contains(&tool)
            || (tool == "edit_file" && !self.writing)
        {
            return Err("invalid_tool");
        }
        self.record(json!({"call_id":id,"tool":tool,"path":path,"state":"started"}))?;
        let result = self.perform(tool, path, args);
        self.current()?;
        let public = match &result {
            Ok(value) => {
                json!({"call_id":id,"tool":tool,"status":"completed","sha256":value.get("sha256")})
            }
            Err(status) => json!({"call_id":id,"tool":tool,"status":status}),
        };
        self.record(public.clone())?;
        self.receipts.push(public);
        result
    }

    fn charge(&mut self, count: usize) -> Result<()> {
        self.bytes = self.bytes.saturating_add(count);
        if self.bytes > TOTAL_BYTES {
            Err("tool_limit")
        } else {
            Ok(())
        }
    }

    fn perform(&mut self, tool: &str, path: &str, args: &Value) -> Result<Value> {
        if tool == "list_files" {
            return self.list(path);
        }
        let (parent, name) = path.rsplit_once('/').unwrap_or(("", path));
        let directory = self.directory(parent, tool == "edit_file")?;
        let before = read(&directory, name)?;
        if tool == "read_file" {
            let (_, bytes) = before.ok_or("file_missing")?;
            self.charge(bytes.len())?;
            return Ok(json!({"path":path,"text":text(&bytes)?,"sha256":digest(&bytes)}));
        }
        let content = args["text"]
            .as_str()
            .filter(|s| s.len() <= FILE_BYTES)
            .ok_or("invalid_tool")?;
        text(content.as_bytes())?;
        self.charge(content.len())?;
        let old = before.as_ref().map(|(_, bytes)| digest(bytes));
        if args["expected_sha256"] != json!(old) {
            return Err("file_changed");
        }
        let temp = format!(".cuckoding-edit-{}", self.calls.len());
        let file = open_at(
            &directory,
            &temp,
            libc::O_WRONLY | libc::O_CREAT | libc::O_EXCL,
        )?;
        let mode = before.as_ref().map_or(0o600, |(m, _)| m.mode() & 0o777);
        if unsafe { libc::fchmod(file.as_raw_fd(), mode as libc::mode_t) } != 0 {
            return Err("write_failed");
        }
        (&file)
            .write_all(content.as_bytes())
            .and_then(|_| file.sync_all())
            .map_err(|_| "write_failed")?;
        self.current()?;
        let current = read(&directory, name)?;
        if current.as_ref().map(|(_, b)| digest(b)) != old
            || current.as_ref().map(|(m, _)| m.ino()) != before.as_ref().map(|(m, _)| m.ino())
        {
            return Err("file_changed");
        }
        let temp = CString::new(temp).unwrap();
        let name = CString::new(name).unwrap();
        let code = unsafe {
            libc::renameat(
                directory.as_raw_fd(),
                temp.as_ptr(),
                directory.as_raw_fd(),
                name.as_ptr(),
            )
        };
        if code != 0 {
            return Err("write_failed");
        }
        directory.sync_all().map_err(|_| "write_failed")?;
        Ok(json!({"path":path,"sha256":digest(content.as_bytes())}))
    }

    fn list(&mut self, path: &str) -> Result<Value> {
        let directory = self.directory(path, false)?;
        let fd = directory
            .try_clone()
            .map_err(|_| "unsafe_file")?
            .into_raw_fd();
        let stream = unsafe { libc::fdopendir(fd) };
        if stream.is_null() {
            unsafe { libc::close(fd) };
            return Err("unsafe_file");
        }
        struct Entries(*mut libc::DIR);
        impl Drop for Entries {
            fn drop(&mut self) {
                unsafe { libc::closedir(self.0) };
            }
        }
        let stream = Entries(stream);
        let mut entries = Vec::new();
        let mut scanned = 0;
        loop {
            unsafe { *libc::__error() = 0 };
            let item = unsafe { libc::readdir(stream.0) };
            if item.is_null() {
                if io::Error::last_os_error().raw_os_error() != Some(0) {
                    return Err("unsafe_file");
                }
                break;
            }
            scanned += 1;
            if scanned > 2000 {
                return Err("tool_limit");
            }
            let name = unsafe { CStr::from_ptr((*item).d_name.as_ptr()) };
            let Ok(name) = name.to_str() else {
                continue;
            };
            let relative = if path.is_empty() {
                name.to_owned()
            } else {
                format!("{path}/{name}")
            };
            if !valid_path(&relative, false) {
                continue;
            }
            let Ok(file) = open_at(&directory, name, libc::O_RDONLY) else {
                continue;
            };
            let metadata = file.metadata().map_err(|_| "unsafe_file")?;
            if metadata.is_dir() || (metadata.is_file() && metadata.nlink() == 1) {
                entries.push(
                    json!({"path":relative,"type":if metadata.is_dir(){"directory"}else{"file"}}),
                );
                if entries.len() > 128 {
                    return Err("tool_limit");
                }
            }
        }
        entries.sort_by(|a, b| a["path"].as_str().cmp(&b["path"].as_str()));
        let value = json!({"entries":entries});
        self.charge(value.to_string().len())?;
        Ok(value)
    }
}

pub(super) fn tools(writing: bool) -> Value {
    let mut tools = vec![
        json!({"name":"list_files","description":"List eligible entries in one workspace directory. Empty path lists the root. Hidden, protected and credential paths are excluded.","inputSchema":{"type":"object","additionalProperties":false,"required":["path"],"properties":{"path":{"type":"string"}}}}),
        json!({"name":"read_file","description":"Read one eligible UTF-8 workspace file up to 32 KiB and return its SHA-256.","inputSchema":{"type":"object","additionalProperties":false,"required":["path"],"properties":{"path":{"type":"string"}}}}),
    ];
    if writing {
        tools.push(json!({"name":"edit_file","description":"Create or replace one eligible UTF-8 file up to 32 KiB. Pass its last read SHA-256, or null only for a new file. Parent directories are created. No commands or protected policy changes.","inputSchema":{"type":"object","additionalProperties":false,"required":["path","expected_sha256","text"],"properties":{"path":{"type":"string"},"expected_sha256":{"type":["string","null"]},"text":{"type":"string"}}}}));
    }
    json!(tools)
}

#[cfg(test)]
pub(super) mod tests {
    use super::*;
    use std::os::unix::fs::{symlink, PermissionsExt};
    use std::sync::atomic::{AtomicUsize, Ordering};
    static SERIAL: AtomicUsize = AtomicUsize::new(0);
    pub const KEY: &str = "11111111-1111-4111-8111-111111111111";

    pub fn fixture() -> (PathBuf, PathBuf, PathBuf, Value) {
        let root = std::env::temp_dir().canonicalize().unwrap().join(format!(
            "cc-task-tools-{}-{}",
            std::process::id(),
            SERIAL.fetch_add(1, Ordering::Relaxed)
        ));
        let profile = root.join("agents/codex");
        let scratch = root.join("scratch");
        let owned = root.join("runtime-home/worktrees").join(KEY);
        let checkout = owned.join("checkout");
        for p in [&profile, &scratch, &owned, &checkout] {
            fs::create_dir_all(p).unwrap();
            fs::set_permissions(p, fs::Permissions::from_mode(0o700)).unwrap();
        }
        let m = fs::metadata(&checkout).unwrap();
        let mut workspace = json!({"key":KEY,"head":"a".repeat(40),"source_device":1,"source_inode":2,"path":checkout,"device":m.dev(),"inode":m.ino()});
        let mut marker = workspace.clone();
        marker.as_object_mut().unwrap().remove("device");
        marker.as_object_mut().unwrap().remove("inode");
        marker["version"] = json!(1);
        fs::write(owned.join("owner.json"), marker.to_string()).unwrap();
        fs::write(checkout.join("source.txt"), "before").unwrap();
        workspace["path"] = json!(checkout);
        let request = json!({"request_id":KEY,"contract":"host-task-tools-v1","access":"write","workspace":workspace,"prompt":"Change source.txt to after using read_file and edit_file.","instructions":"Keep it small."});
        (root, profile, scratch, request)
    }

    #[test]
    fn scoped_reads_cas_edits_and_receipts_survive_without_replay() {
        let (root, profile, scratch, request) = fixture();
        let mut files = Files::new(&profile, &scratch, &request).unwrap();
        let read = files
            .call("read", "read_file", &json!({"path":"source.txt"}))
            .unwrap();
        assert_eq!(read["text"], "before");
        let edit = json!({"path":"source.txt","text":"after","expected_sha256":read["sha256"]});
        assert!(files.call("edit", "edit_file", &edit).is_ok());
        assert_eq!(
            files.call("duplicate", "edit_file", &edit),
            Err("file_changed")
        );
        assert_eq!(files.call("edit", "edit_file", &edit), Err("tool_limit"));
        assert!(files
            .call(
                "new",
                "edit_file",
                &json!({"path":"lib/new.txt","expected_sha256":null,"text":"new"})
            )
            .is_ok());
        assert_eq!(
            fs::read_to_string(files.path.join("source.txt")).unwrap(),
            "after"
        );
        let journal = fs::read_to_string(scratch.join("tool-receipts.jsonl")).unwrap();
        assert!(journal.contains("started") && journal.contains("completed"));
        assert!(!journal.contains("before") && !journal.contains("after"));
        assert!(Files::new(&profile, &scratch, &request).is_err());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn read_only_protected_links_foreign_roots_and_resource_limits_fail_closed() {
        let (root, profile, scratch, mut request) = fixture();
        request["access"] = json!("read");
        let mut files = Files::new(&profile, &scratch, &request).unwrap();
        assert_eq!(
            files.call(
                "w",
                "edit_file",
                &json!({"path":"source.txt","text":"after","expected_sha256":digest(b"before")})
            ),
            Err("invalid_tool")
        );
        for (i, path) in [
            "../outside.txt",
            "/etc/passwd",
            ".git/config",
            ".cuckoding/policy.json",
            "nested/AGENTS.md",
            "a/secret.txt",
            "a/key.pem",
            "x//y",
            "x/./y",
        ]
        .iter()
        .enumerate()
        {
            assert!(files
                .call(&format!("bad-{i}"), "read_file", &json!({"path":path}))
                .is_err());
        }
        fs::write(root.join("outside.txt"), "private-canary").unwrap();
        symlink(root.join("outside.txt"), files.path.join("linked.txt")).unwrap();
        fs::hard_link(root.join("outside.txt"), files.path.join("hard.txt")).unwrap();
        symlink(&root, files.path.join("linked-directory")).unwrap();
        for path in ["linked.txt", "hard.txt", "linked-directory/outside.txt"] {
            assert!(files
                .call(path, "read_file", &json!({"path":path}))
                .is_err());
        }
        fs::write(files.path.join("large.txt"), vec![b'x'; FILE_BYTES + 1]).unwrap();
        assert_eq!(
            files.call("large", "read_file", &json!({"path":"large.txt"})),
            Err("unsupported_file")
        );
        assert!(files
            .call(
                "extra",
                "read_file",
                &json!({"path":"source.txt","command":"bad"})
            )
            .is_err());
        fs::rename(&files.path, files.path.with_extension("old")).unwrap();
        fs::create_dir(&files.path).unwrap();
        assert_eq!(
            files.call("replaced", "read_file", &json!({"path":"source.txt"})),
            Err("unsafe_workspace")
        );
        assert_eq!(
            fs::read_to_string(root.join("outside.txt")).unwrap(),
            "private-canary"
        );
        request["workspace"]["path"] = json!(root);
        assert!(Files::new(&profile, &scratch, &request).is_err());
        fs::remove_dir_all(root).unwrap();
    }
}
