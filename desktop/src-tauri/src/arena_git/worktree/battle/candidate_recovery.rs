//! Read complete retained capture evidence; never create a candidate or receipt.
use super::*;

pub(super) fn recover(git: &Git<'_>, request: &Value, device: u64, inode: u64) -> Result<Value> {
    let key = initial::uuid(&request["key"])?;
    let preparation = &request["preparation"];
    let worktree_key = initial::uuid(&preparation["key"])?;
    let battle = &request["battle"];
    if request.as_object().map(|m| m.len()) != Some(4)
        || preparation.as_object().map(|m| m.len()) != Some(5)
        || key == worktree_key
        || request["key"] == battle["battle_key"]
        || preparation["head"] != battle["head"]
    {
        return Err("invalid_request");
    }
    candidate::valid_changes(&request["files"])?;
    current(git, battle, device, inode)?;
    let parent = git.home.join("worktrees").join(worktree_key);
    let prepared = load(&parent, "receipt.json")?;
    let mut expected_preparation = preparation.clone();
    expected_preparation["status"] = json!("prepared");
    let binding = json!({"request":{"key":worktree_key,"battle":battle},
        "preparation":prepared,"source_device":device,"source_inode":inode});
    if prepared != expected_preparation || load(&parent, "battle.json")? != binding {
        return Err("worktree_mismatch");
    }
    let directory = parent.join(format!("candidate-{key}"));
    let original = json!({"key":key,"preparation":preparation,"files":request["files"]});
    let receipt = load(&directory, "receipt.json")?;
    if receipt.as_object().map(|m| m.len()) != Some(7)
        || receipt["status"] != "candidate_captured"
        || load(&directory, "intent.json")? != original
        || load(&directory, "publication.json")? != receipt
    {
        return Err("candidate_mismatch");
    }
    let verification = json!({"battle":battle,"preparation":preparation,"candidate":receipt});
    verified_candidate(git, &verification, device, inode)?;
    if load(&parent, "receipt.json")? != prepared
        || load(&parent, "battle.json")? != binding
        || load(&directory, "intent.json")? != original
        || load(&directory, "publication.json")? != receipt
        || load(&directory, "receipt.json")? != receipt
    {
        return Err("candidate_mismatch");
    }
    current(git, battle, device, inode)?;
    Ok(receipt)
}
