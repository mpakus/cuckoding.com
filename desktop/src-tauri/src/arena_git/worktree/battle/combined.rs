//! Rebuild compatible captured paths on the current reviewed head; never merge project code.
use super::*;
use std::collections::BTreeMap;

fn entries(values: Vec<Entry>) -> BTreeMap<String, Entry> {
    values
        .into_iter()
        .map(|entry| (entry.path.clone(), entry))
        .collect()
}

fn plan(
    base: &BTreeMap<String, Entry>,
    candidate: &BTreeMap<String, Entry>,
    current: &BTreeMap<String, Entry>,
) -> Result<BTreeMap<String, Entry>> {
    if base.keys().any(|path| !candidate.contains_key(path)) {
        return Err("candidate_mismatch");
    }
    let mut merged = current.clone();
    let mut count = 0;
    let mut bytes = 0;
    for (path, next) in candidate {
        let previous = base.get(path);
        if previous == Some(next) {
            continue;
        }
        count += 1;
        bytes += next.bytes;
        if count > 64
            || next.bytes > 32_768
            || bytes > 524_288
            || !crate::connection::valid_task_path(path, false)
        {
            return Err("candidate_mismatch");
        }
        if current.get(path) != previous && current.get(path) != Some(next) {
            return Err("candidate_conflict");
        }
        merged.insert(path.clone(), next.clone());
    }
    if merged.len() > 10_000 || merged.values().map(|entry| entry.bytes).sum::<usize>() > 67_108_864
    {
        return Err("tree_limit");
    }
    // Compare every prefix as well as full names: APFS case aliases and file/directory
    // collisions must not turn an independent result into an overwrite.
    portable_paths(merged.keys().map(String::as_str)).map_err(|_| "candidate_conflict")?;
    Ok(merged)
}

fn expected(
    git: &Git<'_>,
    request: &Value,
    device: u64,
    inode: u64,
) -> Result<BTreeMap<String, Entry>> {
    let battle = &request["battle"];
    let preparation = &request["preparation"];
    let candidate = &request["candidate"];
    retained(git, battle, device, inode)?;
    source(
        git,
        hash(&battle["base"], 40)?,
        battle["reference"].as_str().ok_or("battle_mismatch")?,
        device,
        inode,
    )?;
    if candidate["status"] != "candidate_captured" || preparation["head"] != candidate["base"] {
        return Err("candidate_mismatch");
    }
    let directory = git
        .home
        .join("worktrees")
        .join(initial::uuid(&preparation["key"])?);
    let binding = load(&directory, "battle.json")?;
    let old_battle = &binding["request"]["battle"];
    let mut stored_preparation = preparation.clone();
    if stored_preparation.get("status").is_none() {
        stored_preparation["status"] = json!("prepared");
    }
    if binding
        != json!({"request":{"key":preparation["key"],"battle":old_battle},
        "preparation":stored_preparation,"source_device":device,"source_inode":inode})
        || old_battle["battle_key"] != battle["battle_key"]
        || old_battle["base"] != battle["base"]
        || old_battle["head"] != candidate["base"]
    {
        return Err("candidate_mismatch");
    }
    retained(git, old_battle, device, inode)?;
    candidate::run(
        git,
        "verify_candidate",
        &json!({"key":candidate["key"],
        "preparation":preparation,"candidate":candidate})
        .to_string(),
        device,
        inode,
    )?;
    let base = hash(&candidate["base"], 40)?;
    let head = hash(&battle["head"], 40)?;
    for (ancestor, descendant) in [(hash(&battle["base"], 40)?, base), (base, head)] {
        if git
            .command(&["merge-base", "--is-ancestor", ancestor, descendant], true)?
            .0
            != 0
        {
            return Err("candidate_mismatch");
        }
    }
    let candidate_head = hash(&candidate["candidate"], 40)?;
    if success(
        git,
        &["rev-list", "--parents", "-n", "1", candidate_head],
        None,
        None,
    )? != format!("{candidate_head} {base}\n").as_bytes()
    {
        return Err("candidate_mismatch");
    }
    plan(
        &entries(tree(git, base)?),
        &entries(tree(git, candidate_head)?),
        &entries(tree(git, head)?),
    )
}

fn directory(git: &Git<'_>, battle: &Value, key: &str, device: u64, inode: u64) -> Result<PathBuf> {
    Ok(retained(git, battle, device, inode)?.join(format!("combination-{key}")))
}

fn reference(key: &str) -> String {
    format!("refs/ccoding/combined/{key}")
}

// Read the original intent and completed proof only; publication alone is not recoverable.
pub(super) fn recover(git: &Git<'_>, request: &Value, device: u64, inode: u64) -> Result<Value> {
    let key = initial::uuid(&request["key"])?;
    if request.as_object().map(|fields| fields.len()) != Some(4)
        || request["key"] == request["battle"]["battle_key"]
    {
        return Err("invalid_request");
    }
    current(git, &request["battle"], device, inode)?;
    let directory = directory(git, &request["battle"], key, device, inode)?;
    let intent = load(&directory, "intent.json")?;
    let expected_intent = json!({"request":{"input":request,
        "configuration_sha256":initial::digest(&configuration(git)?)},
        "source_device":device,"source_inode":inode});
    if intent != expected_intent {
        return Err("candidate_mismatch");
    }
    let receipt = load(&directory, "receipt.json")?;
    if receipt["key"] != key {
        return Err("candidate_mismatch");
    }
    let verification = json!({"battle":request["battle"],
        "preparation":request["preparation"],"candidate":receipt});
    let mut verified = verify(git, &verification, device, inode)?;
    verified["status"] = json!("candidate_combined");
    if verified != receipt
        || load(&directory, "intent.json")? != intent
        || load(&directory, "publication.json")? != receipt
        || load(&directory, "receipt.json")? != receipt
    {
        return Err("candidate_mismatch");
    }
    current(git, &request["battle"], device, inode)?;
    Ok(receipt)
}

pub(super) fn verify(git: &Git<'_>, request: &Value, device: u64, inode: u64) -> Result<Value> {
    current(git, &request["battle"], device, inode)?;
    let receipt = verify_retained(git, request, device, inode)?;
    current(git, &request["battle"], device, inode)?;
    Ok(receipt)
}

// Like captured-candidate verification, this proves retained objects only. Admission,
// post-CAS validation and recovery bind their own exact live battle ref separately.
pub(super) fn verify_retained(
    git: &Git<'_>,
    request: &Value,
    device: u64,
    inode: u64,
) -> Result<Value> {
    let candidate = &request["candidate"];
    let key = initial::uuid(&candidate["key"])?;
    let directory = directory(git, &request["battle"], key, device, inode)?;
    let receipt = load(&directory, "receipt.json")?;
    let intent = load(&directory, "intent.json")?;
    let input = &intent["request"]["input"];
    if candidate != &receipt
        || receipt["status"] != "candidate_combined"
        || intent["source_device"] != device
        || intent["source_inode"] != inode
        || input["key"] != key
        || input["battle"] != request["battle"]
        || input["preparation"] != request["preparation"]
        || receipt["battle_key"] != input["battle"]["battle_key"]
        || receipt["base"] != input["battle"]["head"]
        || receipt["task_base"] != input["candidate"]["base"]
        || receipt["task_candidate_key"] != input["candidate"]["key"]
        || receipt["worktree_key"] != input["preparation"]["key"]
        || receipt["manifest_sha256"] != initial::digest(intent.to_string().as_bytes())
        || load(&directory, "publication.json")? != receipt
        || intent["request"]["configuration_sha256"] != initial::digest(&configuration(git)?)
    {
        return Err("candidate_mismatch");
    }
    let planned = expected(git, input, device, inode)?;
    let head = hash(&receipt["candidate"], 40)?;
    if receipt.as_object().map(|value| value.len()) != Some(10)
        || entries(tree(git, head)?) != planned
        || oid(success(
            git,
            &["rev-parse", "--verify", &reference(key)],
            None,
            None,
        )?)? != head
        || oid(success(
            git,
            &["rev-parse", "--verify", &format!("{head}^{{tree}}")],
            None,
            None,
        )?)? != receipt["tree"]
        || success(git, &["rev-list", "--parents", "-n", "1", head], None, None)?
            != format!("{head} {}\n", hash(&receipt["base"], 40)?).as_bytes()
    {
        return Err("candidate_mismatch");
    }
    if intent["request"]["configuration_sha256"] != initial::digest(&configuration(git)?) {
        return Err("repository_changed");
    }
    source(
        git,
        hash(&request["battle"]["base"], 40)?,
        request["battle"]["reference"]
            .as_str()
            .ok_or("battle_mismatch")?,
        device,
        inode,
    )?;
    let mut result = receipt;
    result["status"] = json!("combined_verified");
    Ok(result)
}

pub(super) fn run(git: &Git<'_>, request: &Value, device: u64, inode: u64) -> Result<Value> {
    let key = initial::uuid(&request["key"])?;
    let config = configuration(git)?;
    let planned = expected(git, request, device, inode)?;
    current(git, &request["battle"], device, inode)?;
    let head = hash(&request["battle"]["head"], 40)?;
    let current_entries = entries(tree(git, head)?);
    let directory = directory(git, &request["battle"], key, device, inode)?;
    let manifest = reserve(
        &directory,
        &json!({"input":request,
        "configuration_sha256":initial::digest(&config)}),
        device,
        inode,
    )
    .map_err(|reason| {
        if reason == "battle_exists" {
            "candidate_exists"
        } else {
            "candidate_incomplete"
        }
    })?;
    let index = directory.join("index");
    success(git, &["read-tree", head], None, Some(&index))?;
    for (path, entry) in &planned {
        if current_entries.get(path) == Some(entry) {
            continue;
        }
        let cache = format!("{},{},{}", entry.mode, entry.oid, path);
        success(
            git,
            &["update-index", "--add", "--cacheinfo", &cache],
            None,
            Some(&index),
        )?;
    }
    let tree_id = oid(success(git, &["write-tree"], None, Some(&index))?)?;
    if entries(tree(git, &tree_id)?) != planned {
        return Err("candidate_mismatch");
    }
    let candidate = oid(success(
        git,
        &[
            "commit-tree",
            &tree_id,
            "-p",
            head,
            "--no-gpg-sign",
            "-m",
            "Cuckoding combined candidate",
        ],
        None,
        Some(&index),
    )?)?;
    let receipt = json!({"status":"candidate_combined","key":key,
        "battle_key":request["battle"]["battle_key"],"worktree_key":request["preparation"]["key"],
        "task_candidate_key":request["candidate"]["key"],"base":head,
        "task_base":request["candidate"]["base"],"candidate":candidate,"tree":tree_id,"manifest_sha256":manifest});
    save(&directory, "publication.json", &receipt)?;
    if configuration(git)? != config || expected(git, request, device, inode)? != planned {
        return Err("repository_changed");
    }
    current(git, &request["battle"], device, inode)?;
    success(
        git,
        &[
            "update-ref",
            "--no-deref",
            &reference(key),
            &candidate,
            &"0".repeat(40),
        ],
        None,
        None,
    )?;
    if configuration(git)? != config || expected(git, request, device, inode)? != planned {
        return Err("repository_changed");
    }
    current(git, &request["battle"], device, inode)?;
    if oid(success(
        git,
        &["rev-parse", "--verify", &reference(key)],
        None,
        None,
    )?)? != candidate
    {
        return Err("candidate_mismatch");
    }
    save(&directory, "receipt.json", &receipt)?;
    Ok(receipt)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn file(path: &str, oid: char) -> Entry {
        Entry {
            path: path.into(),
            mode: "100644".into(),
            oid: oid.to_string().repeat(40),
            bytes: 10,
        }
    }
    fn map(files: &[(&str, char)]) -> BTreeMap<String, Entry> {
        entries(files.iter().map(|(path, oid)| file(path, *oid)).collect())
    }

    #[test]
    fn combination_plan_refuses_overlap_case_prefix_deletion_and_protected_changes() {
        let base = map(&[("a.txt", 'a'), ("b.txt", 'b')]);
        let candidate = map(&[("a.txt", 'c'), ("b.txt", 'b')]);
        let current = map(&[("a.txt", 'a'), ("b.txt", 'd')]);
        assert_eq!(
            plan(&base, &candidate, &current).unwrap()["b.txt"].oid,
            "d".repeat(40)
        );
        assert!(plan(&base, &candidate, &candidate).is_ok());
        assert!(matches!(
            plan(&base, &candidate, &map(&[("a.txt", 'd'), ("b.txt", 'b')])),
            Err("candidate_conflict")
        ));
        for (left, right) in [
            ("new.txt", "NEW.txt"),
            ("dir", "dir/file.txt"),
            ("Dir/a.txt", "dir/b.txt"),
        ] {
            assert!(matches!(
                plan(&map(&[]), &map(&[(left, 'a')]), &map(&[(right, 'b')])),
                Err("candidate_conflict")
            ));
        }
        assert!(matches!(
            plan(&base, &map(&[("a.txt", 'a')]), &base),
            Err("candidate_mismatch")
        ));
        assert!(matches!(
            plan(
                &map(&[]),
                &map(&[(".cuckoding/policy.txt", 'a')]),
                &map(&[])
            ),
            Err("candidate_mismatch")
        ));
        let large = (0..65).map(|n| file(&format!("{n}.txt"), 'a')).collect();
        assert!(matches!(
            plan(&map(&[]), &entries(large), &map(&[])),
            Err("candidate_mismatch")
        ));
    }
}
