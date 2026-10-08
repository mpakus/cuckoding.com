//! Consented detached checkout; failures retain ownership and any partial Git effects.
use super::*;
use std::{collections::HashSet, os::unix::fs::DirBuilderExt};

const TREE_LIMIT: usize = 1_048_576;

fn configuration(git: &Git<'_>) -> Result<Vec<u8>> {
    let path = git.root.join(".git/config");
    let (code, keys) = git.command(
        &[
            "config",
            "--no-includes",
            "--file",
            path.to_str().ok_or("unsafe_config")?,
            "--null",
            "--name-only",
            "--list",
        ],
        false,
    )?;
    if code != 0
        || std::str::from_utf8(&keys)
            .map_err(|_| "unsafe_config")?
            .split('\0')
            .any(|key| key.to_ascii_lowercase().starts_with("filter."))
    {
        return Err("unsafe_config");
    }
    let mut bytes = Vec::new();
    File::open(path)
        .map_err(|_| "unsafe_config")?
        .take(65_537)
        .read_to_end(&mut bytes)
        .map_err(|_| "unsafe_config")?;
    if bytes.len() > 65_536 {
        return Err("metadata_limit");
    }
    Ok(bytes)
}

fn tree(git: &Git<'_>, head: &str) -> Result<()> {
    let (code, listing) = git.command_bounded(
        &["ls-tree", "-r", "-l", "-z", head],
        true,
        None,
        None,
        TREE_LIMIT,
    )?;
    if code != 0 {
        return Err("invalid_repository");
    }
    let mut names = HashSet::new();
    let mut total = 0u64;
    for record in listing.split(|b| *b == 0).filter(|r| !r.is_empty()) {
        git.active()?;
        let record = std::str::from_utf8(record).map_err(|_| "unsafe_tree")?;
        let (fields, path) = record.split_once('\t').ok_or("unsafe_tree")?;
        let fields: Vec<_> = fields.split_whitespace().collect();
        if fields.len() != 4
            || !["100644", "100755"].contains(&fields[0])
            || fields[1] != "blob"
            || initial::paths(&json!([path])).is_err()
            || !names.insert(path.to_lowercase())
        {
            return Err("unsafe_tree");
        }
        let bytes = fields[3].parse::<u64>().map_err(|_| "unsafe_tree")?;
        total = total.checked_add(bytes).ok_or("tree_limit")?;
        if bytes > 8_388_608 || total > 67_108_864 || names.len() > 10_000 {
            return Err("tree_limit");
        }
    }
    Ok(())
}

pub(super) fn run(git: &Git<'_>, extra: &str, device: u64, inode: u64) -> Result<Value> {
    if extra.len() > 512 {
        return Err("invalid_request");
    }
    let request: Value = serde_json::from_str(extra).map_err(|_| "invalid_request")?;
    let key = initial::uuid(&request["key"])?;
    let head = request["head"].as_str().ok_or("invalid_request")?;
    if head.len() != 40 || !head.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err("invalid_request");
    }
    let observed = git.inspect()?;
    if observed["status"] != "existing" || observed["head"] != head {
        return Err("repository_changed");
    }
    let config = configuration(git)?;
    tree(git, head)?;
    let parent = git.home.join("worktrees");
    match fs::DirBuilder::new().mode(0o700).create(&parent) {
        Ok(()) => (),
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => (),
        Err(_) => return Err("worktree_incomplete"),
    }
    private_directory(&parent).map_err(|_| "unsupported_layout")?;
    let owned = parent.join(key);
    fs::DirBuilder::new()
        .mode(0o700)
        .create(&owned)
        .map_err(|_| "worktree_exists")?;
    let checkout = owned.join("checkout");
    let path = checkout.to_str().ok_or("invalid_request")?;
    let owner = json!({"version":1,"key":key,"head":head,"source_device":device,
        "source_inode":inode,"path":path});
    let mut marker = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(owned.join("owner.json"))
        .map_err(|_| "worktree_incomplete")?;
    marker
        .write_all(owner.to_string().as_bytes())
        .map_err(|_| "worktree_incomplete")?;
    marker.sync_all().map_err(|_| "worktree_incomplete")?;
    File::open(&owned)
        .and_then(|f| f.sync_all())
        .map_err(|_| "worktree_incomplete")?;
    git.identity(device, inode)?;
    if git.inspect()?["head"] != head || configuration(git)? != config {
        return Err("repository_changed");
    }
    // No branch creation, pruning, filters, hooks, submodules or remote transport.
    let (code, _) = git.command(
        &[
            "-c",
            "core.attributesFile=/dev/null",
            "-c",
            "core.autocrlf=false",
            "-c",
            "core.sparseCheckout=false",
            "-c",
            "core.protectHFS=true",
            "-c",
            "core.protectNTFS=true",
            "-c",
            "submodule.recurse=false",
            "worktree",
            "add",
            "--quiet",
            "--detach",
            "--lock",
            "--reason",
            key,
            path,
            head,
        ],
        true,
    )?;
    if code != 0 {
        return Err("worktree_incomplete");
    }
    git.identity(device, inode)?;
    if configuration(git)? != config || git.inspect()?["head"] != head {
        return Err("repository_changed");
    }
    let metadata = fs::symlink_metadata(&checkout).map_err(|_| "worktree_incomplete")?;
    if !metadata.is_dir() || checkout.canonicalize().ok().as_deref() != Some(&checkout) {
        return Err("worktree_incomplete");
    }
    Ok(
        json!({"status":"prepared","key":key,"head":head,"path":path,
        "device":metadata.dev(),"inode":metadata.ino()}),
    )
}
