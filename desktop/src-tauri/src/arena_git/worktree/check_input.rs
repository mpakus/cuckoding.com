//! Exact committed candidate input; no VM launch, host share or execution authority.
use super::*;
use sha2::{Digest, Sha256};
use std::{collections::BTreeSet, ffi::CString, io, os::unix::fs::MetadataExt};
#[cfg(test)]
mod tests;

const CONTRACT: &str = "candidate-check-input-v1";
const ARCHIVE_LIMIT: u64 = 83_886_080;
const MANIFEST_LIMIT: u64 = 5_242_880;

fn same(a: &fs::Metadata, b: &fs::Metadata) -> bool {
    a.dev() == b.dev() && a.ino() == b.ino()
}

fn directory(parent: &File, name: &str, create: bool, exclusive: bool) -> Result<File> {
    if create {
        let text = CString::new(name).map_err(|_| "invalid_request")?;
        // SAFETY: parent retains its descriptor; text is a live NUL-terminated component.
        let created = unsafe { libc::mkdirat(parent.as_raw_fd(), text.as_ptr(), 0o700) } == 0;
        if !created
            && (exclusive || io::Error::last_os_error().kind() != io::ErrorKind::AlreadyExists)
        {
            return Err("check_input_exists");
        }
        if created {
            parent.sync_all().map_err(|_| "check_input_incomplete")?;
        }
    }
    let file = initial::open_at(parent, name, libc::O_RDONLY | libc::O_DIRECTORY)
        .map_err(|_| "check_input_mismatch")?;
    let metadata = file.metadata().map_err(|_| "check_input_mismatch")?;
    if metadata.mode() & 0o077 != 0
        || metadata.uid() != parent.metadata().map_err(|_| "check_input_mismatch")?.uid()
    {
        return Err("check_input_mismatch");
    }
    Ok(file)
}

struct Storage {
    home: File,
    parent: File,
    owned: File,
    key: String,
}

impl Storage {
    fn open(git: &Git<'_>, key: &str, create: bool) -> Result<Self> {
        private_directory(git.home).map_err(|_| "check_input_mismatch")?;
        let home = OpenOptions::new()
            .read(true)
            .custom_flags(libc::O_NOFOLLOW | libc::O_DIRECTORY | libc::O_NONBLOCK)
            .open(git.home)
            .map_err(|_| "check_input_mismatch")?;
        // SAFETY: geteuid has no pointer arguments or memory preconditions.
        if home.metadata().map_err(|_| "check_input_mismatch")?.uid() != unsafe { libc::geteuid() }
        {
            return Err("check_input_mismatch");
        }
        let parent = directory(&home, "check-inputs", create, false)?;
        let owned = directory(&parent, key, create, true)?;
        Ok(Self {
            home,
            parent,
            owned,
            key: key.into(),
        })
    }

    fn current(&self, git: &Git<'_>) -> Result<()> {
        private_directory(git.home).map_err(|_| "check_input_mismatch")?;
        let home = fs::symlink_metadata(git.home).map_err(|_| "check_input_mismatch")?;
        let parent = directory(&self.home, "check-inputs", false, false)?;
        let owned = directory(&parent, &self.key, false, false)?;
        if !same(
            &home,
            &self.home.metadata().map_err(|_| "check_input_mismatch")?,
        ) || !same(
            &parent.metadata().map_err(|_| "check_input_mismatch")?,
            &self.parent.metadata().map_err(|_| "check_input_mismatch")?,
        ) || !same(
            &owned.metadata().map_err(|_| "check_input_mismatch")?,
            &self.owned.metadata().map_err(|_| "check_input_mismatch")?,
        ) {
            return Err("check_input_mismatch");
        }
        Ok(())
    }

    fn create(&self, name: &str) -> Result<File> {
        initial::open_at(
            &self.owned,
            name,
            libc::O_WRONLY | libc::O_CREAT | libc::O_EXCL,
        )
        .map_err(|_| "check_input_incomplete")
    }

    fn write(&self, name: &str, bytes: &[u8]) -> Result<()> {
        let mut file = self.create(name)?;
        file.write_all(bytes)
            .and_then(|_| file.sync_all())
            .map_err(|_| "check_input_incomplete")?;
        self.owned.sync_all().map_err(|_| "check_input_incomplete")
    }

    fn read(&self, name: &str, limit: u64) -> Result<Vec<u8>> {
        let file = initial::open_at(&self.owned, name, libc::O_RDONLY)
            .map_err(|_| "check_input_mismatch")?;
        let before = file.metadata().map_err(|_| "check_input_mismatch")?;
        if !before.is_file()
            || before.nlink() != 1
            || before.len() > limit
            || before.mode() & 0o7777 != 0o600
            || before.uid()
                != self
                    .owned
                    .metadata()
                    .map_err(|_| "check_input_mismatch")?
                    .uid()
        {
            return Err("check_input_mismatch");
        }
        let mut bytes = Vec::new();
        (&file)
            .take(limit + 1)
            .read_to_end(&mut bytes)
            .map_err(|_| "check_input_mismatch")?;
        let after = file.metadata().map_err(|_| "check_input_mismatch")?;
        if bytes.len() as u64 != before.len()
            || !same(&before, &after)
            || before.mode() != after.mode()
            || before.len() != after.len()
            || before.mtime() != after.mtime()
            || before.mtime_nsec() != after.mtime_nsec()
            || before.ctime() != after.ctime()
            || before.ctime_nsec() != after.ctime_nsec()
        {
            return Err("check_input_mismatch");
        }
        Ok(bytes)
    }
}

struct Archive<W> {
    file: W,
    digest: Sha256,
    bytes: u64,
    inode: u32,
}

impl<W: Write> Archive<W> {
    fn write(&mut self, bytes: &[u8]) -> Result<()> {
        self.bytes = self
            .bytes
            .checked_add(bytes.len() as u64)
            .ok_or("tree_limit")?;
        if self.bytes > ARCHIVE_LIMIT {
            return Err("tree_limit");
        }
        self.file
            .write_all(bytes)
            .map_err(|_| "check_input_incomplete")?;
        self.digest.update(bytes);
        Ok(())
    }

    fn entry(&mut self, name: &str, mode: u32, uid: u32, bytes: &[u8]) -> Result<()> {
        self.inode += 1;
        if self.inode > 20_000 {
            return Err("tree_limit");
        }
        let mut header = String::from("070701");
        for field in [
            self.inode,
            mode,
            uid,
            uid,
            1,
            0,
            bytes.len() as u32,
            0,
            0,
            0,
            0,
            name.len() as u32 + 1,
            0,
        ] {
            header.push_str(&format!("{field:08x}"));
        }
        self.write(header.as_bytes())?;
        self.write(name.as_bytes())?;
        self.write(&[0])?;
        self.write(&[0; 3][..((4 - self.bytes % 4) % 4) as usize])?;
        self.write(bytes)?;
        self.write(&[0; 3][..((4 - self.bytes % 4) % 4) as usize])
    }
}

fn encode(
    git: &Git<'_>,
    entries: &[Entry],
    input: &Value,
    file: impl Write,
) -> Result<(Vec<u8>, u64, String)> {
    let mut archive = Archive {
        file,
        digest: Sha256::new(),
        bytes: 0,
        inode: 0,
    };
    let mut directories = BTreeSet::from([
        "requests".to_owned(),
        "work".to_owned(),
        "work/checkout".to_owned(),
    ]);
    for entry in entries {
        for (index, _) in entry.path.match_indices('/') {
            directories.insert(format!("work/checkout/{}", &entry.path[..index]));
        }
    }
    if directories.len() + entries.len() + 2 > 20_000 {
        return Err("tree_limit");
    }
    for path in directories {
        git.active()?;
        archive.entry(
            &path,
            0o40755,
            if path.starts_with("work/checkout") {
                1000
            } else {
                0
            },
            b"",
        )?;
    }
    let mut files = Vec::new();
    inspection::each_blob(git, entries, |entry, bytes| {
        archive.entry(
            &format!("work/checkout/{}", entry.path),
            if entry.mode == "100755" {
                0o100755
            } else {
                0o100644
            },
            1000,
            bytes,
        )?;
        files.push(json!({"path":entry.path, "mode":entry.mode, "bytes":bytes.len(), "sha256":initial::digest(bytes)}));
        Ok(true)
    })?;
    let manifest =
        json!({"contract":CONTRACT, "key":input["key"], "worktree_key":input["preparation"]["key"],
        "candidate_sha":input["preparation"]["head"], "tree_sha":input["tree_sha"], "files":files})
        .to_string()
        .into_bytes();
    if manifest.len() as u64 > MANIFEST_LIMIT {
        return Err("tree_limit");
    }
    archive.entry("requests/candidate.json", 0o100444, 0, &manifest)?;
    archive.entry("TRAILER!!!", 0, 0, b"")?;
    Ok((
        manifest,
        archive.bytes,
        format!("{:x}", archive.digest.finalize()),
    ))
}

fn receipt(input: &Value, entries: &[Entry], manifest: &[u8], bytes: u64, hash: &str) -> Value {
    json!({"status":"check_input_prepared", "contract":CONTRACT, "key":input["key"],
        "worktree_key":input["preparation"]["key"], "candidate_sha":input["preparation"]["head"],
        "tree_sha":input["tree_sha"], "intent_sha256":initial::digest(input.to_string().as_bytes()),
        "archive_sha256":hash, "archive_bytes":bytes, "manifest_sha256":initial::digest(manifest),
        "manifest_bytes":manifest.len(), "file_count":entries.len(),
        "content_bytes":entries.iter().map(|entry| entry.bytes).sum::<usize>()})
}

fn source(
    git: &Git<'_>,
    preparation: &Value,
    device: u64,
    inode: u64,
    entries: &[Entry],
    config: &[u8],
) -> Result<()> {
    git.identity(device, inode)?;
    let owned = inspection::owned(git, preparation, device, inode)?;
    if configuration(git)? != config
        || !inspection::index_matches(git, &owned, entries)?
        || !inspection::files_match(git, &owned, entries)?
    {
        return Err("check_input_mismatch");
    }
    Ok(())
}

pub(in super::super) fn run(
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
    let creating = operation == "prepare_check_input";
    if !request
        .as_object()
        .is_some_and(|m| m.len() == if creating { 2 } else { 3 })
        || !request.get("preparation").is_some_and(Value::is_object)
    {
        return Err("invalid_request");
    }
    let key = initial::uuid(&request["key"])?;
    let preparation = &request["preparation"];
    let worktree_key = initial::uuid(&preparation["key"])?;
    let head = candidate::hash(&preparation["head"], 40)?;
    let prepared_path = git.home.join("worktrees").join(worktree_key);
    if candidate::load(&prepared_path, "receipt.json")? != *preparation {
        return Err("check_input_mismatch");
    }
    if git.inspect()?["status"] != "existing" {
        return Err("invalid_repository");
    }
    let config = configuration(git)?;
    let entries = tree(git, head)?;
    portable_paths(entries.iter().map(|e| e.path.as_str()))?;
    source(git, preparation, device, inode, &entries, &config)?;
    let tree_sha = candidate::oid(candidate::success(
        git,
        &["rev-parse", "--verify", &format!("{head}^{{tree}}")],
        None,
        None,
    )?)?;
    let input = json!({"contract":CONTRACT, "key":key, "preparation":preparation,
        "source_device":device, "source_inode":inode, "tree_sha":tree_sha});
    let storage = Storage::open(git, key, creating)?;
    storage.current(git)?;
    if !creating {
        let intent = storage.read("intent.json", 8192)?;
        let retained: Value = serde_json::from_slice(&storage.read("receipt.json", 8192)?)
            .map_err(|_| "check_input_mismatch")?;
        let (expected_manifest, expected_bytes, expected_hash) =
            encode(git, &entries, &input, io::sink())?;
        if serde_json::from_slice::<Value>(&intent).ok().as_ref() != Some(&input)
            || request["input"] != retained
            || retained["intent_sha256"] != initial::digest(&intent)
            || retained
                != receipt(
                    &input,
                    &entries,
                    &expected_manifest,
                    expected_bytes,
                    &expected_hash,
                )
        {
            return Err("check_input_mismatch");
        }
        let archive = storage.read("candidate.cpio", ARCHIVE_LIMIT)?;
        let manifest = storage.read("manifest.json", MANIFEST_LIMIT)?;
        if expected_hash != initial::digest(&archive)
            || expected_bytes != archive.len() as u64
            || manifest != expected_manifest
        {
            return Err("check_input_mismatch");
        }
        source(git, preparation, device, inode, &entries, &config)?;
        storage.current(git)?;
        git.active()?;
        let mut verified = retained;
        verified["status"] = json!("check_input_verified");
        return Ok(verified);
    }
    storage.write("intent.json", input.to_string().as_bytes())?;
    git.active()?;
    let mut archive = storage.create("candidate.cpio")?;
    let (manifest, bytes, hash) = encode(git, &entries, &input, &mut archive)?;
    archive.sync_all().map_err(|_| "check_input_incomplete")?;
    storage.write("manifest.json", &manifest)?;
    source(git, preparation, device, inode, &entries, &config)?;
    storage.current(git)?;
    let captured = storage.read("candidate.cpio", ARCHIVE_LIMIT)?;
    if captured.len() as u64 != bytes || initial::digest(&captured) != hash {
        return Err("check_input_mismatch");
    }
    let result = receipt(&input, &entries, &manifest, bytes, &hash);
    git.active()?;
    storage.write("receipt.json", result.to_string().as_bytes())?;
    storage.current(git)?;
    git.active()?;
    Ok(result)
}
