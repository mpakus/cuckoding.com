//! Hash-bound candidate objects and app refs; never stage or move the user's checkout.
use super::*;
use inspection::{files_match, index_matches, owned, Owned};

pub(super) fn hash(value: &Value, size: usize) -> Result<&str> {
    value
        .as_str()
        .filter(|v| v.len() == size && v.bytes().all(|b| b.is_ascii_hexdigit()))
        .ok_or("invalid_request")
}

pub(super) fn success(
    git: &Git<'_>,
    args: &[&str],
    input: Option<Vec<u8>>,
    index: Option<&Path>,
) -> Result<Vec<u8>> {
    let (code, bytes) = git.command_input(args, true, input, index)?;
    if code == 0 {
        Ok(bytes)
    } else {
        Err("candidate_incomplete")
    }
}

pub(super) fn oid(bytes: Vec<u8>) -> Result<String> {
    let text = String::from_utf8(bytes).map_err(|_| "candidate_incomplete")?;
    let value = json!(text.trim());
    hash(&value, 40)
        .map(str::to_owned)
        .map_err(|_| "candidate_incomplete")
}

pub(super) fn save(directory: &Path, name: &str, value: &Value) -> Result<()> {
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW)
        .open(directory.join(name))
        .map_err(|_| "candidate_incomplete")?;
    file.write_all(value.to_string().as_bytes())
        .and_then(|_| file.sync_all())
        .map_err(|_| "candidate_incomplete")?;
    File::open(directory)
        .and_then(|f| f.sync_all())
        .map_err(|_| "candidate_incomplete")
}

pub(super) fn load(directory: &Path, name: &str) -> Result<Value> {
    private_directory(directory).map_err(|_| "candidate_mismatch")?;
    let directory = File::open(directory).map_err(|_| "candidate_mismatch")?;
    let (_, bytes) =
        initial::read_at(&directory, name, 32_768).map_err(|_| "candidate_mismatch")?;
    serde_json::from_slice(&bytes).map_err(|_| "candidate_mismatch")
}

fn stable(
    git: &Git<'_>,
    preparation: &Value,
    config: &[u8],
    base: &[Entry],
    expected: &[Entry],
    device: u64,
    inode: u64,
) -> Result<Owned> {
    git.identity(device, inode)?;
    if configuration(git)? != config {
        return Err("repository_changed");
    }
    let current = owned(git, preparation, device, inode)?;
    if !index_matches(git, &current, base)? || !files_match(git, &current, expected)? {
        return Err("candidate_mismatch");
    }
    Ok(current)
}

pub(in super::super::super) fn run(
    git: &Git<'_>,
    operation: &str,
    extra: &str,
    device: u64,
    inode: u64,
) -> Result<Value> {
    if extra.len() > 32_768 {
        return Err("invalid_request");
    }
    let request: Value = serde_json::from_str(extra).map_err(|_| "invalid_request")?;
    let key = initial::uuid(&request["key"])?;
    let preparation = &request["preparation"];
    let base = hash(&preparation["head"], 40)?;
    let observed = git.inspect()?;
    if observed["status"] != "existing" {
        return Err("invalid_repository");
    }
    let config = configuration(git)?;
    let workspace = owned(git, preparation, device, inode)?;
    let entries = tree(git, base)?;
    let parent = git
        .home
        .join("worktrees")
        .join(initial::uuid(&preparation["key"])?);
    let directory = parent.join(format!("candidate-{key}"));
    let reference = format!("refs/ccoding/candidates/{key}");
    if operation == "verify_candidate" {
        if !request.as_object().is_some_and(|m| m.len() == 3) {
            return Err("invalid_request");
        }
        let retained = load(&directory, "receipt.json")?;
        if request["candidate"] != retained
            || retained["key"] != key
            || retained["base"] != base
            || retained["worktree_key"] != preparation["key"]
        {
            return Err("candidate_mismatch");
        }
        let intent = load(&directory, "intent.json")?;
        if intent["preparation"] != *preparation
            || retained["manifest_sha256"] != initial::digest(intent.to_string().as_bytes())
        {
            return Err("candidate_mismatch");
        }
        let candidate = hash(&retained["candidate"], 40)?;
        if oid(success(
            git,
            &["rev-parse", "--verify", &reference],
            None,
            None,
        )?)? != candidate
            || oid(success(
                git,
                &["rev-parse", "--verify", &format!("{candidate}^{{tree}}")],
                None,
                None,
            )?)? != retained["tree"]
        {
            return Err("candidate_mismatch");
        }
        stable(
            git,
            preparation,
            &config,
            &entries,
            &tree(git, candidate)?,
            device,
            inode,
        )?;
        let mut result = retained;
        result["status"] = json!("candidate_verified");
        return Ok(result);
    }
    if operation != "capture_candidate" || !request.as_object().is_some_and(|m| m.len() == 3) {
        return Err("invalid_request");
    }
    let changes = request["files"]
        .as_array()
        .filter(|v| v.len() <= 64)
        .ok_or("invalid_request")?;
    let mut names = HashSet::new();
    for file in changes {
        let path = file["path"]
            .as_str()
            .filter(|p| crate::connection::valid_task_path(p, false))
            .ok_or("invalid_request")?;
        hash(&file["sha256"], 64)?;
        if !file.as_object().is_some_and(|m| m.len() == 2)
            || !names.insert(path.to_ascii_lowercase())
        {
            return Err("invalid_request");
        }
    }
    if !index_matches(git, &workspace, &entries)? {
        return Err("candidate_mismatch");
    }
    // Exclusive intent prevents retries after any object or ref could have been written.
    fs::DirBuilder::new()
        .mode(0o700)
        .create(&directory)
        .map_err(|_| "candidate_exists")?;
    save(&directory, "intent.json", &request)?;
    let index = directory.join("index");
    success(git, &["read-tree", base], None, Some(&index))?;
    let mut total = 0;
    for file in changes {
        git.active()?;
        let path = file["path"].as_str().unwrap();
        let (metadata, bytes) = initial::read_at(&workspace.checkout, path, 32_768)?;
        total += bytes.len();
        if total > 524_288 || metadata["sha256"] != file["sha256"] {
            return Err("candidate_mismatch");
        }
        let mode = entries
            .iter()
            .find(|entry| entry.path == path)
            .map(|entry| entry.mode.as_str())
            .unwrap_or("100644");
        if metadata["mode"] != mode {
            return Err("candidate_mismatch");
        }
        let blob = oid(success(
            git,
            &["hash-object", "-w", "--no-filters", "--stdin"],
            Some(bytes),
            Some(&index),
        )?)?;
        let entry = format!("{mode},{blob},{path}");
        success(
            git,
            &["update-index", "--add", "--cacheinfo", &entry],
            None,
            Some(&index),
        )?;
    }
    let candidate_tree = oid(success(git, &["write-tree"], None, Some(&index))?)?;
    let expected = tree(git, &candidate_tree)?;
    stable(
        git,
        preparation,
        &config,
        &entries,
        &expected,
        device,
        inode,
    )?;
    let candidate = oid(success(
        git,
        &[
            "commit-tree",
            &candidate_tree,
            "-p",
            base,
            "--no-gpg-sign",
            "-m",
            "Cuckoding task candidate",
        ],
        None,
        Some(&index),
    )?)?;
    let receipt = json!({"status":"candidate_captured","key":key,"worktree_key":preparation["key"],"base":base,
        "candidate":candidate,"tree":candidate_tree,"manifest_sha256":initial::digest(request.to_string().as_bytes())});
    save(&directory, "publication.json", &receipt)?;
    stable(
        git,
        preparation,
        &config,
        &entries,
        &expected,
        device,
        inode,
    )?;
    success(
        git,
        &[
            "update-ref",
            "--no-deref",
            &reference,
            &candidate,
            &"0".repeat(40),
        ],
        None,
        None,
    )?;
    // A crash between publication and receipt is uncertain, not replayable success.
    stable(
        git,
        preparation,
        &config,
        &entries,
        &expected,
        device,
        inode,
    )?;
    save(&directory, "receipt.json", &receipt)?;
    Ok(receipt)
}
