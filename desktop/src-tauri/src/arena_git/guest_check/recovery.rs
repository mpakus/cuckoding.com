//! Read complete original check proof; no VM launch, signal, replay or workflow authority.
use super::*;

const RECOVERY: &str = "retained-guest-check-v1";

fn validate_query(query: &Value) -> Result<&str> {
    let feedback = query["feedback"] == FEEDBACK;
    if query["contract"] != RECOVERY
        || !query
            .as_object()
            .is_some_and(|m| m.len() == 4 + usize::from(feedback))
        || (query.get("feedback").is_some() && !feedback)
        || !query["check"].as_object().is_some_and(|m| m.len() == 8)
        || !query["image"].is_object()
    {
        return Err("invalid_request");
    }
    initial::uuid(&query["image"]["key"])?;
    let mut check = query["check"].clone();
    check["manifest_sha256"] = json!("a".repeat(64));
    check["image_spec_sha256"] = query["image"]["spec_sha256"].clone();
    let mut shape = json!({"contract":CONTRACT,"key":query["key"],"check":check,
        "image":{},"input":{},"deadline_unix_ms":1});
    if feedback {
        shape["feedback"] = json!(FEEDBACK);
    }
    validate_shape(&shape)?;
    initial::uuid(&query["key"])
}

fn retained_scope(store: &Store, query: &Value, source: &Value) -> Result<(Value, Vec<u8>)> {
    let scope = store.read("admission.json", 32768)?;
    if store.read("request.json", 32768)? != scope {
        return Err("cleanup_uncertain");
    }
    let parsed: Value = serde_json::from_slice(&scope).map_err(|_| "invalid_output")?;
    let request = &parsed["request"];
    validate_shape(request)?;
    let mut check = request["check"].clone();
    check.as_object_mut().unwrap().remove("manifest_sha256");
    check.as_object_mut().unwrap().remove("image_spec_sha256");
    if parsed != json!({"source":source,"request":request})
        || request["key"] != query["key"]
        || check != query["check"]
        || request["image"] != json!({"key":query["image"]["key"],"image":query["image"]})
        || request.get("feedback") != query.get("feedback")
        || request["input"]["key"] != query["check"]["input_key"]
        || request["input"]["preparation"]["key"] != query["check"]["input_key"]
        || request["check"]["image_spec_sha256"] != query["image"]["spec_sha256"]
    {
        return Err("cleanup_uncertain");
    }
    Ok((request.clone(), scope))
}

fn retained_receipt(
    store: &Store,
    request: &Value,
    scope: &[u8],
    kernel: &[u8],
    ramdisk: &[u8],
) -> Result<Value> {
    let intent_bytes = store.read("intent.json", 32768)?;
    let intent: Value = serde_json::from_slice(&intent_bytes).map_err(|_| "invalid_output")?;
    let expected = json!({"contract":CONTRACT,"key":request["key"],"check":request["check"],
        "deadline_unix_ms":request["deadline_unix_ms"],"request_sha256":initial::digest(scope),
        "kernel_sha256":initial::digest(kernel),"ramdisk_sha256":initial::digest(ramdisk),
        "keeper_sha256":initial::digest(KEEPER)});
    if intent != expected
        || store.keeper()? != KEEPER
        || store.read("kernel", 134_217_728)? != kernel
        || store.read("ramdisk.cpio.gz", 201_326_592)? != ramdisk
    {
        return Err("cleanup_uncertain");
    }
    let bytes = store.read("keeper-stdout", 8192)?;
    let mut row = closure(store, &bytes, &intent, &initial::digest(&intent_bytes))?;
    if !matches!(row["status"].as_str(), Some("passed" | "failed")) {
        return Err("cleanup_uncertain");
    }
    let output = store.read("output.log", 65536)?;
    if row["stdout_bytes"] != output.len() || row["stdout_sha256"] != initial::digest(&output) {
        return Err("invalid_output");
    }
    row["check_sha256"] = json!(binding(&request["check"]));
    row["cleanup_verified"] = json!(true);
    attach_feedback(&mut row, request, Some(&output));
    let retained: Value = serde_json::from_slice(&store.read("receipt.json", 16384)?)
        .map_err(|_| "invalid_output")?;
    if retained != row
        || store.read("request.json", 32768)? != scope
        || store.read("admission.json", 32768)? != scope
        || store.read("intent.json", 32768)? != intent_bytes
    {
        return Err("cleanup_uncertain");
    }
    store.current()?;
    Ok(row)
}

pub(in super::super) fn run(git: &Git<'_>, extra: &str, device: u64, inode: u64) -> Result<Value> {
    if extra.len() > 32768 {
        return Err("invalid_request");
    }
    let query: Value = serde_json::from_str(extra).map_err(|_| "invalid_request")?;
    let key = validate_query(&query)?;
    git.active()?;
    let store = Store::retained_run(git.home, key)?;
    let source = json!({"path":git.root,"device":device,"inode":inode});
    let (request, scope) = retained_scope(&store, &query, &source)?;
    let (image, kernel, base) = check_image::verified_files(git.home, &request["image"])?;
    git.active()?;
    let (input, archive) = worktree::check_input_bytes(git, &request["input"], device, inode)?;
    if input["candidate_sha"] != request["check"]["candidate_sha"]
        || input["manifest_sha256"] != request["check"]["manifest_sha256"]
        || image["spec_sha256"] != request["check"]["image_spec_sha256"]
    {
        return Err("check_input_mismatch");
    }
    let mut gzip = GzEncoder::new(Vec::new(), Compression::default());
    gzip.write_all(&archive)
        .and_then(|_| gzip.write_all(&config_archive(request["check"].to_string().as_bytes())))
        .map_err(|_| "invalid_output")?;
    let mut ramdisk = base;
    ramdisk.extend(gzip.finish().map_err(|_| "invalid_output")?);
    git.active()?;
    let result = retained_receipt(&store, &request, &scope, &kernel, &ramdisk)?;
    git.identity(device, inode)?;
    git.active()?;
    Ok(result)
}

#[cfg(test)]
mod tests;
