//! Sequential app refs. Every mutation has an exclusive durable intent; never replay one.
use super::*;
use candidate::{hash, load, oid, save, success};
use std::path::PathBuf;

fn reference(key: &str) -> String {
    format!("refs/heads/ccoding/battles/{key}")
}

fn source(git: &Git<'_>, head: &str, reference: &str, device: u64, inode: u64) -> Result<()> {
    git.identity(device, inode)?;
    let observed = git.inspect()?;
    if observed["status"] != "existing" || observed["head"] != head {
        return Err("repository_changed");
    }
    let (code, branch) = git.command(&["symbolic-ref", "--quiet", "HEAD"], true)?;
    if ![0, 1].contains(&code) || branch == format!("{reference}\n").as_bytes() {
        return Err("battle_mismatch");
    }
    Ok(())
}

fn reserve(path: &Path, request: &Value, device: u64, inode: u64) -> Result<String> {
    fs::DirBuilder::new()
        .mode(0o700)
        .create(path)
        .map_err(|_| "battle_exists")?;
    let intent = json!({"request":request,"source_device":device,"source_inode":inode});
    save(path, "intent.json", &intent).map_err(|_| "battle_incomplete")?;
    // Persist the new intent directory before any Git ref can move.
    File::open(path.parent().ok_or("battle_incomplete")?)
        .and_then(|file| file.sync_all())
        .map_err(|_| "battle_incomplete")?;
    Ok(initial::digest(intent.to_string().as_bytes()))
}

fn retained(git: &Git<'_>, battle: &Value, device: u64, inode: u64) -> Result<PathBuf> {
    let battle_key = initial::uuid(&battle["battle_key"])?;
    let key = initial::uuid(&battle["key"])?;
    let reference = reference(battle_key);
    hash(&battle["base"], 40)?;
    hash(&battle["head"], 40)?;
    if battle["reference"] != reference {
        return Err("battle_mismatch");
    }
    let parent = git.home.join("battles");
    private_directory(&parent).map_err(|_| "battle_mismatch")?;
    let root = parent.join(battle_key);
    private_directory(&root).map_err(|_| "battle_mismatch")?;
    let directory = match battle["status"].as_str() {
        Some("battle_created") if key == battle_key && battle["base"] == battle["head"] => {
            root.clone()
        }
        Some("battle_integrated") if key != battle_key => root.join(format!("integration-{key}")),
        _ => return Err("battle_mismatch"),
    };
    let receipt = load(&directory, "receipt.json").map_err(|_| "battle_mismatch")?;
    let intent = load(&directory, "intent.json").map_err(|_| "battle_mismatch")?;
    if *battle != receipt
        || intent["source_device"] != device
        || intent["source_inode"] != inode
        || intent["request"]["key"] != key
        || battle["manifest_sha256"] != initial::digest(intent.to_string().as_bytes())
    {
        return Err("battle_mismatch");
    }
    Ok(root)
}

fn current(git: &Git<'_>, battle: &Value, device: u64, inode: u64) -> Result<()> {
    retained(git, battle, device, inode)?;
    let reference = battle["reference"].as_str().ok_or("battle_mismatch")?;
    source(git, hash(&battle["base"], 40)?, reference, device, inode)?;
    let (code, _) = git.command(&["symbolic-ref", "--quiet", reference], true)?;
    if code != 1 {
        return Err("battle_mismatch");
    }
    let (code, bytes) = git.command(&["rev-parse", "--verify", reference], true)?;
    if code != 0 || oid(bytes)? != battle["head"] {
        return Err("battle_stale");
    }
    configuration(git)?;
    Ok(())
}

fn verified_candidate(git: &Git<'_>, request: &Value, device: u64, inode: u64) -> Result<String> {
    let battle = &request["battle"];
    current(git, battle, device, inode)?;
    candidate_head(git, request, device, inode)
}

fn candidate_head(git: &Git<'_>, request: &Value, device: u64, inode: u64) -> Result<String> {
    let battle = &request["battle"];
    let candidate = &request["candidate"];
    if request["preparation"]["head"] != battle["head"] || candidate["base"] != battle["head"] {
        return Err("battle_stale");
    }
    let verify =
        json!({"key":candidate["key"],"preparation":request["preparation"],"candidate":candidate});
    candidate::run(git, "verify_candidate", &verify.to_string(), device, inode)?;
    let head = hash(&candidate["candidate"], 40)?;
    let expected = format!("{head} {}\n", hash(&battle["head"], 40)?);
    if success(git, &["rev-list", "--parents", "-n", "1", head], None, None)? != expected.as_bytes()
    {
        return Err("candidate_mismatch");
    }
    Ok(head.to_owned())
}

// Read existing evidence only. In particular, publication without a receipt is
// not enough to reconstruct success after a crash.
fn recover_integration(git: &Git<'_>, request: &Value, device: u64, inode: u64) -> Result<Value> {
    let key = initial::uuid(&request["key"])?;
    let battle = &request["battle"];
    if request.as_object().map(|m| m.len()) != Some(4) || request["key"] == battle["battle_key"] {
        return Err("invalid_request");
    }
    let root = retained(git, battle, device, inode)?;
    let directory = root.join(format!("integration-{key}"));
    let intent = json!({"request":request,"source_device":device,"source_inode":inode});
    if load(&directory, "intent.json")? != intent {
        return Err("battle_mismatch");
    }
    let head = candidate_head(git, request, device, inode)?;
    let expected = json!({"status":"battle_integrated","key":key,"battle_key":battle["battle_key"],"base":battle["base"],
        "previous_head":battle["head"],"head":head,"reference":battle["reference"],"candidate_key":request["candidate"]["key"],
        "manifest_sha256":initial::digest(intent.to_string().as_bytes())});
    if load(&directory, "publication.json")? != expected
        || load(&directory, "receipt.json")? != expected
    {
        return Err("battle_mismatch");
    }
    current(git, &expected, device, inode)?;
    Ok(expected)
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
    let fields = request.as_object().ok_or("invalid_request")?.len();
    if operation == "recover_integration" {
        return recover_integration(git, &request, device, inode);
    }
    if operation == "verify_battle" {
        if fields != 1 {
            return Err("invalid_request");
        }
        current(git, &request["battle"], device, inode)?;
        let mut receipt = request["battle"].clone();
        receipt["status"] = json!("battle_verified");
        return Ok(receipt);
    }
    let key = initial::uuid(&request["key"])?;
    if operation == "create_battle" {
        if fields != 2 {
            return Err("invalid_request");
        }
        let head = hash(&request["head"], 40)?;
        let reference = reference(key);
        source(git, head, &reference, device, inode)?;
        let config = configuration(git)?;
        tree(git, head)?;
        let parent = git.home.join("battles");
        match fs::DirBuilder::new().mode(0o700).create(&parent) {
            Ok(()) => (),
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => (),
            Err(_) => return Err("battle_incomplete"),
        }
        private_directory(&parent).map_err(|_| "battle_mismatch")?;
        let directory = parent.join(key);
        let manifest = reserve(&directory, &request, device, inode)?;
        let receipt = json!({"status":"battle_created","key":key,"battle_key":key,"base":head,"head":head,"reference":reference,"manifest_sha256":manifest});
        save(&directory, "publication.json", &receipt).map_err(|_| "battle_incomplete")?;
        source(git, head, &reference, device, inode)?;
        if configuration(git)? != config {
            return Err("repository_changed");
        }
        success(
            git,
            &[
                "update-ref",
                "--no-deref",
                &reference,
                head,
                &"0".repeat(40),
            ],
            None,
            None,
        )
        .map_err(|_| "battle_incomplete")?;
        source(git, head, &reference, device, inode)?;
        if configuration(git)? != config {
            return Err("repository_changed");
        }
        save(&directory, "receipt.json", &receipt).map_err(|_| "battle_incomplete")?;
        current(git, &receipt, device, inode)?;
        return Ok(receipt);
    }
    let battle = &request["battle"];
    current(git, battle, device, inode)?;
    if operation == "battle_worktree" {
        let head = match fields {
            2 => hash(&battle["head"], 40)?.to_owned(),
            4 => verified_candidate(git, &request, device, inode)?,
            _ => return Err("invalid_request"),
        };
        return prepare(git, key, &head, device, inode, || {
            if fields == 4 {
                verified_candidate(git, &request, device, inode).map(|_| ())
            } else {
                current(git, battle, device, inode)
            }
        });
    }
    if operation != "integrate_candidate" || fields != 4 || request["key"] == battle["battle_key"] {
        return Err("invalid_request");
    }
    let head = verified_candidate(git, &request, device, inode)?;
    let root = retained(git, battle, device, inode)?;
    let directory = root.join(format!("integration-{key}"));
    let manifest = reserve(&directory, &request, device, inode)?;
    let receipt = json!({"status":"battle_integrated","key":key,"battle_key":battle["battle_key"],"base":battle["base"],
        "previous_head":battle["head"],"head":head,"reference":battle["reference"],"candidate_key":request["candidate"]["key"],"manifest_sha256":manifest});
    save(&directory, "publication.json", &receipt).map_err(|_| "battle_incomplete")?;
    verified_candidate(git, &request, device, inode)?;
    success(
        git,
        &[
            "update-ref",
            "--no-deref",
            battle["reference"].as_str().ok_or("battle_mismatch")?,
            &head,
            hash(&battle["head"], 40)?,
        ],
        None,
        None,
    )
    .map_err(|_| "battle_incomplete")?;
    // A missing receipt after ref publication is uncertain; no retry can fill it in.
    git.identity(device, inode)?;
    let verify = json!({"key":request["candidate"]["key"],"preparation":request["preparation"],"candidate":request["candidate"]});
    candidate::run(git, "verify_candidate", &verify.to_string(), device, inode)?;
    save(&directory, "receipt.json", &receipt).map_err(|_| "battle_incomplete")?;
    current(git, &receipt, device, inode)?;
    Ok(receipt)
}
