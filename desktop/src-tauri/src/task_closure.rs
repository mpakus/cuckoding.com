//! Public provider closure only. Never a recovered result or process/session replay.
use crate::probe::private_directory;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    ffi::CString,
    fs::{self, File, OpenOptions},
    io::{self, BufRead, Read, Write},
    os::{
        fd::{AsRawFd, FromRawFd},
        unix::fs::{MetadataExt, OpenOptionsExt},
    },
    path::Path,
};

type Result<T> = std::result::Result<T, &'static str>;
pub(crate) const POLICY: &str = "retained-provider-closure-v1";
const LIMIT: usize = 8192;

fn uuid(id: &str) -> bool {
    id.len() == 36
        && id.bytes().enumerate().all(|(i, b)| {
            if [8, 13, 18, 23].contains(&i) {
                b == b'-'
            } else {
                b.is_ascii_hexdigit() && !b.is_ascii_uppercase()
            }
        })
}

pub(crate) fn valid_closure(value: &Value) -> bool {
    value.as_object().is_some_and(|m| m.len() == 7)
        && value["version"] == POLICY
        && value["attempt_sha256"].as_str().is_some_and(|s| {
            s.len() == 64
                && s.bytes()
                    .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
        })
        && value["agent_id"]
            .as_str()
            .is_some_and(|s| s == "codex" || uuid(s))
        && matches!(value["kind"].as_str(), Some("codex" | "cursor"))
        && value["identity"].as_object().is_some_and(|m| m.len() == 6)
        && value["identity"]["path"].as_str().is_some_and(|s| {
            Path::new(s).is_absolute() && s.len() <= 4096 && !s.chars().any(char::is_control)
        })
        && ["device", "inode", "size", "modified", "changed"]
            .iter()
            .all(|k| value["identity"][k].as_u64().is_some())
        && value["model"].as_str().is_some_and(identifier)
        && (value["effort"].as_str().is_some_and(identifier)
            || (value["kind"] == "cursor" && value["effort"].is_null()))
}

fn identifier(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 128
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"._-/".contains(&b))
}

fn open_at(parent: &File, name: &str, flags: i32) -> Result<File> {
    let name = CString::new(name).map_err(|_| "invalid_closure")?;
    // SAFETY: parent owns a live directory FD; the fixed/validated leaf is NUL-terminated.
    let fd = unsafe {
        libc::openat(
            parent.as_raw_fd(),
            name.as_ptr(),
            flags | libc::O_NOFOLLOW | libc::O_CLOEXEC | libc::O_NONBLOCK,
            0o600,
        )
    };
    if fd < 0 {
        Err("closure_unavailable")
    } else {
        // SAFETY: openat returned a new owned FD, transferred exactly once.
        Ok(unsafe { File::from_raw_fd(fd) })
    }
}

fn read(parent: &File, name: &str) -> Result<Vec<u8>> {
    let file = open_at(parent, name, libc::O_RDONLY)?;
    let before = file.metadata().map_err(|_| "closure_unavailable")?;
    // SAFETY: geteuid has no arguments or memory effects.
    if !before.is_file()
        || before.nlink() != 1
        || before.mode() & 0o077 != 0
        || before.uid() != unsafe { libc::geteuid() }
        || before.len() > LIMIT as u64
    {
        return Err("invalid_closure");
    }
    let mut bytes = Vec::new();
    (&file)
        .take((LIMIT + 1) as u64)
        .read_to_end(&mut bytes)
        .map_err(|_| "closure_unavailable")?;
    let after = file.metadata().map_err(|_| "closure_unavailable")?;
    if bytes.len() != before.len() as usize
        || before.ctime() != after.ctime()
        || before.ctime_nsec() != after.ctime_nsec()
        || before.len() != after.len()
    {
        return Err("invalid_closure");
    }
    Ok(bytes)
}

fn private_fd(file: &File) -> Result<()> {
    let metadata = file.metadata().map_err(|_| "invalid_closure")?;
    // SAFETY: geteuid has no arguments or memory effects.
    if metadata.mode() & 0o077 != 0 || metadata.uid() != unsafe { libc::geteuid() } {
        return Err("invalid_closure");
    }
    Ok(())
}

fn root_directory(root: &Path) -> Result<File> {
    private_directory(root).map_err(|_| "invalid_closure")?;
    let root = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC)
        .open(root)
        .map_err(|_| "invalid_closure")?;
    if read(&root, ".ccoding-rebuild-v1")? != b"ccoding-rebuild-v1\n" {
        return Err("invalid_closure");
    }
    private_fd(&root)?;
    Ok(root)
}

fn directory(root: &Path, id: &str) -> Result<File> {
    if !uuid(id) {
        return Err("invalid_closure");
    }
    let root = root_directory(root)?;
    let parent = open_at(
        &root,
        "provider-closures",
        libc::O_RDONLY | libc::O_DIRECTORY,
    )?;
    private_fd(&parent)?;
    let directory = open_at(&parent, id, libc::O_RDONLY | libc::O_DIRECTORY)?;
    private_fd(&directory)?;
    Ok(directory)
}

fn create_at(parent: &File, name: &str, existing: bool) -> Result<File> {
    let leaf = CString::new(name).map_err(|_| "invalid_closure")?;
    // SAFETY: parent owns a live directory FD; the fixed/validated leaf is NUL-terminated.
    if unsafe { libc::mkdirat(parent.as_raw_fd(), leaf.as_ptr(), 0o700) } != 0
        && !(existing && io::Error::last_os_error().raw_os_error() == Some(libc::EEXIST))
    {
        return Err("closure_unavailable");
    }
    let directory = open_at(parent, name, libc::O_RDONLY | libc::O_DIRECTORY)?;
    private_fd(&directory)?;
    parent.sync_all().map_err(|_| "closure_unavailable")?;
    Ok(directory)
}

fn save(parent: &File, name: &str, value: &Value) -> Result<()> {
    let bytes = value.to_string();
    if bytes.len() > LIMIT {
        return Err("invalid_closure");
    }
    let mut file = open_at(parent, name, libc::O_WRONLY | libc::O_CREAT | libc::O_EXCL)?;
    file.write_all(bytes.as_bytes())
        .and_then(|_| file.sync_all())
        .and_then(|_| parent.sync_all())
        .map_err(|_| "closure_unavailable")
}

pub(crate) struct Journal {
    directory: File,
    intent: Value,
}

impl Journal {
    pub(crate) fn start(
        path: &Path,
        profile: &Path,
        scratch: &Path,
        kind: &str,
        request: &Value,
        model: &str,
        effort: Option<&str>,
    ) -> Result<Option<Self>> {
        let Some(closure) = request.get("closure") else {
            return Ok(None);
        };
        if !valid_closure(closure)
            || closure["kind"] != kind
            || closure["model"] != model
            || closure["effort"] != json!(effort)
            || closure["identity"]["path"].as_str() != path.to_str()
        {
            return Err("invalid_closure");
        }
        let id = request["request_id"].as_str().ok_or("invalid_closure")?;
        let agent = closure["agent_id"].as_str().ok_or("invalid_closure")?;
        let root = profile
            .parent()
            .filter(|p| p.file_name().is_some_and(|s| s == "agents"))
            .and_then(Path::parent)
            .ok_or("invalid_closure")?;
        if profile != root.join("agents").join(agent)
            || scratch != root.join("probes").join(format!("{id}-1"))
        {
            return Err("invalid_closure");
        }
        private_directory(profile).map_err(|_| "invalid_closure")?;
        private_directory(scratch).map_err(|_| "invalid_closure")?;
        let identity = &closure["identity"];
        let metadata = fs::metadata(identity["path"].as_str().ok_or("invalid_closure")?)
            .map_err(|_| "invalid_closure")?;
        if !metadata.is_file()
            || metadata.mode() & 0o111 == 0
            || identity["device"] != metadata.dev()
            || identity["inode"] != metadata.ino()
            || identity["size"] != metadata.len()
            || identity["modified"] != metadata.mtime()
            || identity["changed"] != metadata.ctime()
        {
            return Err("invalid_closure");
        }
        if !uuid(id) {
            return Err("invalid_closure");
        }
        let root = root_directory(root)?;
        let parent = create_at(&root, "provider-closures", true)?;
        let directory = create_at(&parent, id, false)?;
        let intent = json!({"request_id":id,"closure":closure});
        save(&directory, "provider-closure-intent.json", &intent)?;
        Ok(Some(Self { directory, intent }))
    }

    pub(crate) fn finish(self, result: &mut Value) {
        if result["cleanup_verified"] != true {
            return;
        }
        let receipt = json!({"intent":self.intent,"cleanup_verified":true,"pid":result["pid"],"spawned_at_ms":result["spawned_at_ms"],"elapsed_ms":result["elapsed_ms"]});
        if !public_fields(&receipt)
            || save(&self.directory, "provider-closure.json", &receipt).is_err()
        {
            result["status"] = json!("journal_failed");
            if let Some(object) = result.as_object_mut() {
                object.remove("report");
            }
        }
    }
}

fn public_fields(value: &Value) -> bool {
    value["pid"]
        .as_u64()
        .is_some_and(|n| n > 0 && n <= i32::MAX as u64)
        && value["spawned_at_ms"]
            .as_u64()
            .is_some_and(|n| n > 0 && n < 10_000_000_000_000)
        && value["elapsed_ms"].as_u64().is_some_and(|n| n <= 900_000)
}

pub(crate) fn inspect(request: &Value) -> Result<Value> {
    if !request.as_object().is_some_and(|m| m.len() == 2) || !valid_closure(&request["closure"]) {
        return Err("invalid_closure");
    }
    let id = request["request_id"].as_str().ok_or("invalid_closure")?;
    let directory = directory(&std::env::current_dir().map_err(|_| "invalid_closure")?, id)?;
    inspect_at(&directory, request)
}

fn inspect_at(directory: &File, request: &Value) -> Result<Value> {
    let intent: Value = serde_json::from_slice(&read(directory, "provider-closure-intent.json")?)
        .map_err(|_| "invalid_closure")?;
    let bytes = read(directory, "provider-closure.json")?;
    let receipt: Value = serde_json::from_slice(&bytes).map_err(|_| "invalid_closure")?;
    if intent != *request
        || receipt["intent"] != intent
        || !receipt.as_object().is_some_and(|m| m.len() == 5)
        || receipt["cleanup_verified"] != true
        || !public_fields(&receipt)
    {
        return Err("invalid_closure");
    }
    Ok(
        json!({"status":"provider_closed","request_id":request["request_id"],"attempt_sha256":request["closure"]["attempt_sha256"],"agent_id":request["closure"]["agent_id"],"kind":request["closure"]["kind"],"cleanup_verified":true,"pid":receipt["pid"],"spawned_at_ms":receipt["spawned_at_ms"],"elapsed_ms":receipt["elapsed_ms"],"receipt_sha256":format!("{:x}",Sha256::digest(bytes))}),
    )
}

pub(crate) fn main() {
    let mut bytes = Vec::new();
    let result = io::stdin()
        .lock()
        .take((LIMIT + 1) as u64)
        .read_until(b'\n', &mut bytes)
        .ok()
        .filter(|n| *n <= LIMIT)
        .and_then(|_| serde_json::from_slice::<Value>(&bytes).ok())
        .ok_or("invalid_closure")
        .and_then(|request| inspect(&request));
    let _ = writeln!(
        io::stdout(),
        "{}",
        result.unwrap_or_else(|status| json!({"status":status}))
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        os::unix::fs::PermissionsExt,
        path::PathBuf,
        sync::atomic::{AtomicUsize, Ordering},
    };
    static SERIAL: AtomicUsize = AtomicUsize::new(0);

    fn fixture(kind: &str) -> (PathBuf, PathBuf, PathBuf, Value) {
        let root = std::env::temp_dir().canonicalize().unwrap().join(format!(
            "cuckoding-closure-{}-{}",
            std::process::id(),
            SERIAL.fetch_add(1, Ordering::SeqCst)
        ));
        fs::create_dir(&root).unwrap();
        fs::set_permissions(&root, fs::Permissions::from_mode(0o700)).unwrap();
        let id = "11111111-2222-4333-8444-555555555555";
        let profile = root.join("agents/codex");
        let scratch = root.join("probes").join(format!("{id}-1"));
        for directory in [
            root.join("agents"),
            profile.clone(),
            root.join("probes"),
            scratch.clone(),
        ] {
            fs::create_dir(&directory).unwrap();
            fs::set_permissions(directory, fs::Permissions::from_mode(0o700)).unwrap();
        }
        fs::write(root.join(".ccoding-rebuild-v1"), "ccoding-rebuild-v1\n").unwrap();
        fs::set_permissions(
            root.join(".ccoding-rebuild-v1"),
            fs::Permissions::from_mode(0o600),
        )
        .unwrap();
        let metadata = fs::metadata("/usr/bin/true").unwrap();
        let request = json!({"request_id":id,"closure":{"version":POLICY,"attempt_sha256":"a".repeat(64),"agent_id":"codex","kind":kind,
            "identity":{"path":"/usr/bin/true","device":metadata.dev(),"inode":metadata.ino(),"size":metadata.len(),"modified":metadata.mtime(),"changed":metadata.ctime()},
            "model":"test-model","effort":if kind=="codex" {json!("low")} else {Value::Null}}});
        (root, profile, scratch, request)
    }

    fn start(profile: &Path, scratch: &Path, request: &Value) -> Result<Journal> {
        Journal::start(
            Path::new("/usr/bin/true"),
            profile,
            scratch,
            request["closure"]["kind"].as_str().unwrap(),
            request,
            "test-model",
            request["closure"]["effort"].as_str(),
        )
        .map(Option::unwrap)
    }

    fn closed() -> Value {
        json!({"cleanup_verified":true,"pid":123,"spawned_at_ms":1000,"elapsed_ms":20,"report":"private-canary","raw_provider":"private-canary"})
    }

    #[test]
    fn closure_never_accepts_unverified_or_foreign_evidence() {
        assert!(!valid_closure(&json!({})));
        assert!(inspect(&json!({"request_id":"foreign"})).is_err());
    }

    #[test]
    fn publication_is_exclusive_bound_and_contains_no_provider_data() {
        for kind in ["codex", "cursor"] {
            let (root, profile, scratch, request) = fixture(kind);
            assert!(valid_closure(&request["closure"]));
            let journal = start(&profile, &scratch, &request).unwrap();
            assert_eq!(
                fs::read_dir(&scratch).unwrap().count(),
                0,
                "Runtime scratch stays empty and cannot read closure evidence"
            );
            assert!(start(&profile, &scratch, &request).is_err());
            let directory = directory(&root, request["request_id"].as_str().unwrap()).unwrap();
            assert!(inspect_at(&directory, &request).is_err());
            journal.finish(&mut closed());
            let receipt = inspect_at(&directory, &request).unwrap();
            assert_eq!(receipt["status"], "provider_closed");
            assert_eq!(receipt["attempt_sha256"], "a".repeat(64));
            assert!(
                !String::from_utf8(read(&directory, "provider-closure.json").unwrap())
                    .unwrap()
                    .contains("private-canary")
            );
            let mut foreign = request.clone();
            foreign["closure"]["attempt_sha256"] = json!("b".repeat(64));
            assert!(inspect_at(&directory, &foreign).is_err());
            foreign = request.clone();
            foreign["closure"]["agent_id"] = json!("11111111-2222-4333-8444-555555555556");
            assert!(inspect_at(&directory, &foreign).is_err());
            fs::remove_dir_all(root).unwrap();
        }
    }

    #[test]
    fn uncertain_partial_linked_or_changed_closure_is_not_proof() {
        let (root, profile, scratch, request) = fixture("codex");
        let journal = start(&profile, &scratch, &request).unwrap();
        let retained = root
            .join("provider-closures")
            .join(request["request_id"].as_str().unwrap());
        let directory = directory(&root, request["request_id"].as_str().unwrap()).unwrap();
        let mut result = closed();
        result["cleanup_verified"] = json!(false);
        journal.finish(&mut result);
        assert!(!retained.join("provider-closure.json").exists());
        assert!(inspect_at(&directory, &request).is_err());
        save(&directory,"provider-closure.json",&json!({"intent":request,"cleanup_verified":false,"pid":123,"spawned_at_ms":1000,"elapsed_ms":20})).unwrap();
        assert!(inspect_at(&directory, &request).is_err());
        fs::remove_file(retained.join("provider-closure.json")).unwrap();
        std::os::unix::fs::symlink(
            retained.join("provider-closure-intent.json"),
            retained.join("provider-closure.json"),
        )
        .unwrap();
        assert!(inspect_at(&directory, &request).is_err());
        fs::remove_file(retained.join("provider-closure.json")).unwrap();
        fs::hard_link(
            retained.join("provider-closure-intent.json"),
            retained.join("provider-closure.json"),
        )
        .unwrap();
        assert!(inspect_at(&directory, &request).is_err());
        fs::remove_file(retained.join("provider-closure.json")).unwrap();
        fs::write(retained.join("provider-closure.json"), b"{").unwrap();
        fs::set_permissions(
            retained.join("provider-closure.json"),
            fs::Permissions::from_mode(0o600),
        )
        .unwrap();
        assert!(inspect_at(&directory, &request).is_err());
        fs::write(
            retained.join("provider-closure.json"),
            vec![b'x'; LIMIT + 1],
        )
        .unwrap();
        assert!(inspect_at(&directory, &request).is_err());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn wrong_runtime_profile_scratch_or_identity_is_refused_before_intent() {
        let (root, profile, scratch, mut request) = fixture("codex");
        assert!(Journal::start(
            Path::new("/bin/false"),
            &profile,
            &scratch,
            "codex",
            &request,
            "test-model",
            Some("low")
        )
        .is_err());
        assert!(Journal::start(
            Path::new("/usr/bin/true"),
            &profile,
            &scratch,
            "cursor",
            &request,
            "test-model",
            Some("low")
        )
        .is_err());
        assert!(start(&profile, &root, &request).is_err());
        request["closure"]["identity"]["inode"] = json!(0);
        assert!(start(&profile, &scratch, &request).is_err());
        assert!(!root.join("provider-closures").exists());
        fs::remove_dir_all(root).unwrap();
    }
}
