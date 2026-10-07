//! First commit only: explicit file snapshots, no existing index or history.
use super::*;
use sha2::{Digest, Sha256};
use std::{
    ffi::{CStr, CString},
    os::fd::FromRawFd,
};

const FILE_LIMIT: u64 = 1_048_576;
const TOTAL_LIMIT: usize = 8_388_608;

fn digest(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn paths(value: &Value) -> Result<Vec<&str>> {
    let values = value.as_array().ok_or("invalid_selection")?;
    if values.len() > 16 {
        return Err("selection_limit");
    }
    let mut paths = Vec::new();
    for value in values {
        let path = value.as_str().ok_or("invalid_selection")?;
        if path.is_empty()
            || path.len() > 240
            || path.chars().any(char::is_control)
            || path.contains('\\')
            || path.starts_with('-')
            || path.split('/').any(|part| {
                let part = part.to_ascii_lowercase();
                part.is_empty()
                    || part == "."
                    || part == ".."
                    || part == ".git"
                    || part.starts_with(".env")
                    || part == ".ssh"
                    || part == ".aws"
                    || part == ".azure"
                    || part == ".gnupg"
                    || part == "credentials"
                    || part.starts_with("id_rsa")
                    || part.starts_with("id_ed25519")
                    || part.ends_with(".pem")
                    || part.ends_with(".key")
            })
            || paths.contains(&path)
        {
            return Err("invalid_selection");
        }
        paths.push(path);
    }
    Ok(paths)
}

fn open_at(directory: &File, name: &str, flags: i32) -> Result<File> {
    let name = CString::new(name).map_err(|_| "invalid_selection")?;
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

fn read_file(git: &Git<'_>, path: &str) -> Result<(Value, Vec<u8>)> {
    git.active()?;
    let mut directory = git.directory.try_clone().map_err(|_| "unsafe_file")?;
    let parts: Vec<_> = path.split('/').collect();
    for part in &parts[..parts.len() - 1] {
        directory = open_at(&directory, part, libc::O_RDONLY | libc::O_DIRECTORY)?;
    }
    let file = open_at(&directory, parts[parts.len() - 1], libc::O_RDONLY)?;
    let before = file.metadata().map_err(|_| "unsafe_file")?;
    if !before.is_file() || before.nlink() != 1 {
        return Err("unsafe_file");
    }
    if before.len() > FILE_LIMIT {
        return Err("selection_limit");
    }
    let mut bytes = Vec::new();
    (&file)
        .take(FILE_LIMIT + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| "unsafe_file")?;
    let after = file.metadata().map_err(|_| "unsafe_file")?;
    git.active()?;
    if bytes.len() as u64 != before.len()
        || before.len() != after.len()
        || before.mtime_nsec() != after.mtime_nsec()
        || before.mtime() != after.mtime()
        || before.ctime_nsec() != after.ctime_nsec()
        || before.ctime() != after.ctime()
    {
        return Err("preview_changed");
    }
    let mode = if before.mode() & 0o111 != 0 {
        "100755"
    } else {
        "100644"
    };
    Ok((
        json!({"path":path,"bytes":bytes.len(),"sha256":digest(&bytes),"mode":mode}),
        bytes,
    ))
}

fn preview(git: &Git<'_>, paths: &[&str]) -> Result<(Value, Vec<Vec<u8>>)> {
    if git.inspect()?["status"] != "unborn" {
        return Err("initial_only");
    }
    if git.command(&["show-ref", "--quiet"], true)?.0 != 1 {
        return Err("initial_only");
    }
    if fs::symlink_metadata(git.root.join(".git/index")).is_ok() {
        return Err("index_present");
    }
    let (code, branch) = git.command(&["symbolic-ref", "--quiet", "HEAD"], true)?;
    let branch = std::str::from_utf8(&branch)
        .map_err(|_| "invalid_repository")?
        .trim();
    if code != 0
        || !branch.starts_with("refs/heads/")
        || branch.len() > 256
        || branch.chars().any(char::is_control)
    {
        return Err("invalid_repository");
    }
    if git.command(&["check-ref-format", branch], false)?.0 != 0 {
        return Err("invalid_repository");
    }
    let metadata = fs::symlink_metadata(git.root.join(".git")).map_err(|_| "repository_changed")?;
    let git_dir = open_at(&git.directory, ".git", libc::O_RDONLY | libc::O_DIRECTORY)?;
    let config_file = open_at(&git_dir, "config", libc::O_RDONLY)?;
    let config_meta = config_file.metadata().map_err(|_| "repository_changed")?;
    if !config_meta.is_file() || config_meta.nlink() != 1 {
        return Err("unsafe_config");
    }
    let mut config = Vec::new();
    config_file
        .take(65_537)
        .read_to_end(&mut config)
        .map_err(|_| "repository_changed")?;
    if config.len() > 65_536 {
        return Err("metadata_limit");
    }
    let repository = digest(
        &serde_json::to_vec(&json!([
            metadata.dev(),
            metadata.ino(),
            branch,
            digest(&config)
        ]))
        .map_err(|_| "invalid_repository")?,
    );
    let mut files = Vec::new();
    let mut contents = Vec::new();
    let mut total = 0;
    for path in paths {
        let (file, bytes) = read_file(git, path)?;
        total += bytes.len();
        if total > TOTAL_LIMIT {
            return Err("selection_limit");
        }
        files.push(file);
        contents.push(bytes);
    }
    let snapshot = json!({"branch":branch,"repository":repository,"files":files});
    if serde_json::to_vec(&snapshot)
        .map_err(|_| "invalid_selection")?
        .len()
        > 7_000
    {
        return Err("selection_limit");
    }
    Ok((snapshot, contents))
}

// Remove only the exact lock inode this helper created, even after directory moves.
struct Lock<'a> {
    directory: &'a File,
    name: CString,
    file: File,
}
impl<'a> Lock<'a> {
    fn new(directory: &'a File, name: &CStr) -> Result<Self> {
        let fd = unsafe {
            libc::openat(
                directory.as_raw_fd(),
                name.as_ptr(),
                libc::O_WRONLY | libc::O_CREAT | libc::O_EXCL | libc::O_NOFOLLOW | libc::O_CLOEXEC,
                0o600,
            )
        };
        if fd < 0 {
            return Err("repository_busy");
        }
        Ok(Self {
            directory,
            name: name.to_owned(),
            file: unsafe { File::from_raw_fd(fd) },
        })
    }
}
impl Drop for Lock<'_> {
    fn drop(&mut self) {
        let mut metadata: libc::stat = unsafe { std::mem::zeroed() };
        if let Ok(owned) = self.file.metadata() {
            unsafe {
                if libc::fstatat(
                    self.directory.as_raw_fd(),
                    self.name.as_ptr(),
                    &mut metadata,
                    libc::AT_SYMLINK_NOFOLLOW,
                ) == 0
                    && metadata.st_ino == owned.ino()
                    && metadata.st_dev as u64 == owned.dev()
                {
                    libc::unlinkat(self.directory.as_raw_fd(), self.name.as_ptr(), 0);
                }
            }
        }
    }
}

fn success(git: &Git<'_>, args: &[&str], input: Option<Vec<u8>>, index: &Path) -> Result<Vec<u8>> {
    let (code, bytes) = git.command_input(args, true, input, Some(index))?;
    if code == 0 {
        Ok(bytes)
    } else {
        Err("commit_incomplete")
    }
}

fn oid(bytes: Vec<u8>) -> Result<String> {
    let hash = String::from_utf8(bytes).map_err(|_| "commit_incomplete")?;
    let hash = hash.trim();
    if hash.len() != 40 || !hash.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err("commit_incomplete");
    }
    Ok(hash.into())
}

fn uuid(value: &Value) -> Result<&str> {
    let value = value.as_str().ok_or("invalid_request")?;
    if value.len() != 36
        || !value.bytes().enumerate().all(|(i, b)| {
            if [8, 13, 18, 23].contains(&i) {
                b == b'-'
            } else {
                b.is_ascii_hexdigit()
            }
        })
    {
        return Err("invalid_request");
    }
    Ok(value)
}

pub(super) fn run(
    git: &Git<'_>,
    operation: &str,
    extra: &str,
    device: u64,
    inode: u64,
) -> Result<Value> {
    if extra.len() > 8192 {
        return Err("invalid_request");
    }
    let request: Value = serde_json::from_str(extra).map_err(|_| "invalid_request")?;
    if operation == "preview" {
        let selected = paths(&request["paths"])?;
        let (preview, _) = preview(git, &selected)?;
        git.identity(device, inode)?;
        return Ok(json!({"status":"previewed","preview":preview}));
    }
    let expected = &request["preview"];
    let selected = Value::Array(
        expected["files"]
            .as_array()
            .ok_or("invalid_request")?
            .iter()
            .map(|f| f["path"].clone())
            .collect(),
    );
    let selected = paths(&selected)?;
    let key = uuid(&request["key"])?;
    let preview_id = uuid(&request["preview_id"])?;
    // Cooperating Git writers honor these locks; index/ref publication is still not atomic.
    let metadata = open_at(&git.directory, ".git", libc::O_RDONLY | libc::O_DIRECTORY)?;
    let mut index_lock = Lock::new(&metadata, c"index.lock")?;
    let _head_lock = Lock::new(&metadata, c"HEAD.lock")?;
    let (observed, contents) = preview(git, &selected)?;
    if &observed != expected {
        return Err("preview_changed");
    }
    git.identity(device, inode)?;
    let scratch = git.home.join(format!("initial-commit-{key}"));
    // Retain the candidate index after any uncertain effect; never reuse a command directory.
    std::os::unix::fs::DirBuilderExt::mode(&mut fs::DirBuilder::new(), 0o700)
        .create(&scratch)
        .map_err(|_| "commit_incomplete")?;
    let index = scratch.join("index");
    success(git, &["read-tree", "--empty"], None, &index)?;
    for (file, bytes) in observed["files"]
        .as_array()
        .ok_or("invalid_request")?
        .iter()
        .zip(contents)
    {
        let hash = oid(success(
            git,
            &["hash-object", "-w", "--no-filters", "--stdin"],
            Some(bytes),
            &index,
        )?)?;
        let entry = format!(
            "{},{},{}",
            file["mode"].as_str().ok_or("invalid_request")?,
            hash,
            file["path"].as_str().ok_or("invalid_request")?
        );
        success(
            git,
            &["update-index", "--add", "--cacheinfo", &entry],
            None,
            &index,
        )?;
    }
    let tree = oid(success(git, &["write-tree"], None, &index)?)?;
    let head = oid(success(
        git,
        &[
            "commit-tree",
            &tree,
            "--no-gpg-sign",
            "-m",
            "Initialize Arena with Cuckoding",
        ],
        None,
        &index,
    )?)?;
    git.identity(device, inode)?;
    // Check the snapshot again after preparation, before publishing an index or branch.
    if preview(git, &selected)?.0 != observed {
        return Err("preview_changed");
    }
    let candidate = fs::read(&index).map_err(|_| "commit_incomplete")?;
    index_lock
        .file
        .write_all(&candidate)
        .map_err(|_| "commit_incomplete")?;
    index_lock
        .file
        .sync_all()
        .map_err(|_| "commit_incomplete")?;
    git.active()?;
    // Exclusive link cannot overwrite a newly appeared index. On interruption retain it.
    if unsafe {
        libc::linkat(
            metadata.as_raw_fd(),
            c"index.lock".as_ptr(),
            metadata.as_raw_fd(),
            c"index".as_ptr(),
            0,
        )
    } != 0
    {
        return Err("index_present");
    }
    let branch = observed["branch"].as_str().ok_or("invalid_request")?;
    // Git's transaction API cannot verify symbolic HEAD and create its referent together.
    // Keep HEAD locked and publish an absent loose ref exclusively, with Git's ref locks.
    let _packed_lock = Lock::new(&metadata, c"packed-refs.lock")?;
    let mut directory = metadata.try_clone().map_err(|_| "commit_incomplete")?;
    let parts: Vec<_> = branch.split('/').collect();
    for part in &parts[..parts.len() - 1] {
        let name = CString::new(*part).map_err(|_| "invalid_repository")?;
        // mkdirat never replaces an existing entry; open_at refuses links and non-directories.
        unsafe {
            libc::mkdirat(directory.as_raw_fd(), name.as_ptr(), 0o700);
        }
        directory = open_at(&directory, part, libc::O_RDONLY | libc::O_DIRECTORY)?;
    }
    let name = CString::new(parts[parts.len() - 1]).map_err(|_| "invalid_repository")?;
    let lock_name = CString::new(format!("{}.lock", name.to_str().unwrap()))
        .map_err(|_| "invalid_repository")?;
    let mut branch_lock = Lock::new(&directory, &lock_name)?;
    if git.command(&["show-ref", "--quiet"], true)?.0 != 1 {
        return Err("initial_only");
    }
    branch_lock
        .file
        .write_all(format!("{head}\n").as_bytes())
        .map_err(|_| "commit_incomplete")?;
    branch_lock
        .file
        .sync_all()
        .map_err(|_| "commit_incomplete")?;
    git.identity(device, inode)?;
    if unsafe {
        libc::linkat(
            directory.as_raw_fd(),
            lock_name.as_ptr(),
            directory.as_raw_fd(),
            name.as_ptr(),
            0,
        )
    } != 0
    {
        return Err("commit_incomplete");
    }
    directory.sync_all().map_err(|_| "commit_incomplete")?;
    metadata.sync_all().map_err(|_| "commit_incomplete")?;
    Ok(json!({"status":"committed","head":head,"tree":tree,"preview_id":preview_id}))
}
