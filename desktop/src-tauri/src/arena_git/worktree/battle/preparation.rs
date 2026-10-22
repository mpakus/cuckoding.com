//! Read a completed writer preparation; missing evidence is never reconstructed.
use super::*;

pub(super) fn recover(git: &Git<'_>, request: &Value, device: u64, inode: u64) -> Result<Value> {
    let key = initial::uuid(&request["key"])?;
    let battle = &request["battle"];
    if request.as_object().map(|fields| fields.len()) != Some(2)
        || request["key"] == battle["battle_key"]
    {
        return Err("invalid_request");
    }
    current(git, battle, device, inode)?;
    let directory = git.home.join("worktrees").join(key);
    let receipt = load(&directory, "receipt.json")?;
    let expected_binding = json!({"request":request,"preparation":receipt,
        "source_device":device,"source_inode":inode});
    if receipt.as_object().map(|fields| fields.len()) != Some(6)
        || receipt["status"] != "prepared"
        || receipt["key"] != key
        || receipt["head"] != battle["head"]
        || load(&directory, "battle.json")? != expected_binding
    {
        return Err("worktree_mismatch");
    }
    let inspected = inspection::inspect(git, &receipt.to_string(), device, inode)?;
    if inspected["status"] != "worktree_unchanged"
        || load(&directory, "receipt.json")? != receipt
        || load(&directory, "battle.json")? != expected_binding
    {
        return Err("worktree_mismatch");
    }
    current(git, battle, device, inode)?;
    Ok(receipt)
}
