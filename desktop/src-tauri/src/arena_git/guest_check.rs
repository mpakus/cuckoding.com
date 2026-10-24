//! Fixed VM operation; it is not admitted by current battle grants.
use super::*;
use crate::check_image::{self, Store};
use flate2::{write::GzEncoder, Compression};
use std::{
    os::unix::fs::PermissionsExt,
    time::{SystemTime, UNIX_EPOCH},
};
#[cfg(test)]
mod tests;

const CONTRACT: &str = "isolated-guest-check-v1";
const FEEDBACK: &str = "bounded-guest-feedback-v1";
const KEEPER: &[u8] = include_bytes!(env!("CCODING_CHECK_KEEPER"));
fn now() -> Result<u64> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| "timeout")?
        .as_millis()
        .try_into()
        .map_err(|_| "timeout")
}
fn time_valid(time: Option<u64>, baseline: u64, deadline: u64) -> bool {
    time.is_some_and(|t| baseline <= t && t < deadline)
}
fn relative(value: &str) -> bool {
    value.len() <= 240
        && !value.chars().any(char::is_control)
        && !value.contains('\\')
        && value.split('/').all(|s| !["", ".", ".."].contains(&s))
}
fn validate(request: &Value) -> Result<(&str, u64)> {
    let feedback = request["feedback"] == FEEDBACK;
    if !request
        .as_object()
        .is_some_and(|m| m.len() == 6 + usize::from(feedback))
        || (request.get("feedback").is_some() && !feedback)
        || request["contract"] != CONTRACT
    {
        return Err("invalid_request");
    }
    let key = initial::uuid(&request["key"])?;
    let deadline = request["deadline_unix_ms"]
        .as_u64()
        .ok_or("invalid_request")?;
    let time = now()?;
    if deadline <= time || deadline - time > 360_000 {
        return Err("timeout");
    }
    let check = &request["check"];
    if !check.as_object().is_some_and(|m| m.len() == 10)
        || !matches!(check["toolchain"].as_str(), Some("npm" | "mix"))
        || !check["directory"]
            .as_str()
            .is_some_and(|d| d == "." || relative(d))
        || !check["timeout_seconds"]
            .as_u64()
            .is_some_and(|n| (1..=300).contains(&n))
        || !check["arguments"].as_array().is_some_and(|args| {
            args.len() <= 16
                && args.iter().all(|a| {
                    a.as_str()
                        .is_some_and(|s| s.len() <= 256 && !s.chars().any(char::is_control))
                })
        })
    {
        return Err("invalid_request");
    }
    for field in ["request_id", "check_id", "input_key"] {
        initial::uuid(&check[field])?;
    }
    for (field, length) in [
        ("candidate_sha", 40),
        ("manifest_sha256", 64),
        ("image_spec_sha256", 64),
    ] {
        let value = check[field].as_str().ok_or("invalid_request")?;
        if value.len() != length
            || !value
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        {
            return Err("invalid_request");
        }
    }
    Ok((key, deadline))
}

fn attach_feedback(row: &mut Value, request: &Value, output: Option<&[u8]>) {
    if request["feedback"] != FEEDBACK
        || row["status"] != "failed"
        || row["cleanup_verified"] != true
    {
        return;
    }
    let Some(output) = output else { return };
    let mut text = String::new();
    let mut escape = 0;
    for c in String::from_utf8_lossy(output).chars() {
        match escape {
            1 => {
                escape = match c {
                    '[' => 2,
                    ']' => 3,
                    _ => 0,
                }
            }
            2 => {
                if ('@'..='~').contains(&c) {
                    escape = 0
                }
            }
            3 => match c {
                '\u{7}' => escape = 0,
                '\u{1b}' => escape = 4,
                _ => {}
            },
            4 => escape = if c == '\\' { 0 } else { 3 },
            _ => {
                if c == '\u{1b}' {
                    escape = 1;
                } else if (c == '\n' || c == '\t' || !c.is_control())
                    && !matches!(c, '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}')
                {
                    text.push(c);
                }
            }
        }
    }
    let truncated = text.len() > 4096;
    let mut limit = text.len().min(4096);
    while !text.is_char_boundary(limit) {
        limit -= 1;
    }
    text.truncate(limit);
    row["failure_output"] = json!({"version":FEEDBACK,"excerpt_sha256":initial::digest(text.as_bytes()),
        "excerpt_bytes":text.len(),"excerpt":text,"truncated":truncated});
}
fn binding(check: &Value) -> String {
    let mut bytes = Vec::new();
    let mut field = |value: &str| {
        bytes.extend((value.len() as u32).to_be_bytes());
        bytes.extend(value.as_bytes());
    };
    for key in [
        "request_id",
        "check_id",
        "input_key",
        "candidate_sha",
        "manifest_sha256",
        "image_spec_sha256",
        "toolchain",
        "directory",
    ] {
        field(check[key].as_str().unwrap());
    }
    let arguments = check["arguments"].as_array().unwrap();
    bytes.extend((arguments.len() as u32).to_be_bytes());
    for value in arguments {
        let text = value.as_str().unwrap();
        bytes.extend((text.len() as u32).to_be_bytes());
        bytes.extend(text.as_bytes());
    }
    bytes.extend(check["timeout_seconds"].as_u64().unwrap().to_be_bytes());
    initial::digest(&bytes)
}

fn config_archive(bytes: &[u8]) -> Vec<u8> {
    let mut result = Vec::new();
    for (index, (name, mode, data)) in [
        ("requests", 0o40700, b"".as_slice()),
        ("requests/check.json", 0o100400, bytes),
        ("TRAILER!!!", 0, b"".as_slice()),
    ]
    .into_iter()
    .enumerate()
    {
        let mut header = String::from("070701");
        for n in [
            index as u32 + 1,
            mode,
            0,
            0,
            1,
            0,
            data.len() as u32,
            0,
            0,
            0,
            0,
            name.len() as u32 + 1,
            0,
        ] {
            header.push_str(&format!("{n:08x}"));
        }
        result.extend(header.as_bytes());
        result.extend(name.as_bytes());
        result.push(0);
        result.resize((result.len() + 3) & !3, 0);
        result.extend(data);
        result.resize((result.len() + 3) & !3, 0);
    }
    result
}
fn closure(store: &Store, bytes: &[u8], intent: &Value, intent_hash: &str) -> Result<Value> {
    let row: Value = serde_json::from_slice(bytes).map_err(|_| "invalid_output")?;
    let retained: Value =
        serde_json::from_slice(&store.read("closure.json", 8192)?).map_err(|_| "invalid_output")?;
    let required = [
        "contract",
        "key",
        "request_id",
        "check_id",
        "input_key",
        "candidate_sha",
        "intent_sha256",
        "native_state",
        "vm_closed",
        "status",
    ];
    let optional = [
        "source_unchanged",
        "stdout_bytes",
        "observed_stdout_bytes",
        "stdout_sha256",
        "exit_code",
    ];
    if row != retained
        || !row.as_object().is_some_and(|m| {
            required.iter().all(|k| m.contains_key(*k))
                && m.keys()
                    .all(|k| required.contains(&k.as_str()) || optional.contains(&k.as_str()))
        })
        || row["contract"] != CONTRACT
        || row["key"] != intent["key"]
        || row["intent_sha256"] != intent_hash
        || row["native_state"].as_u64() != Some(0)
        || row["vm_closed"] != true
    {
        return Err("cleanup_uncertain");
    }
    for field in ["request_id", "check_id", "input_key", "candidate_sha"] {
        if row[field] != intent["check"][field] {
            return Err("cleanup_uncertain");
        }
    }
    let status = row["status"].as_str().ok_or("invalid_output")?;
    if ![
        "passed",
        "failed",
        "source_changed",
        "output_limit",
        "timeout",
        "cancelled",
        "launch_failed",
        "invalid_output",
    ]
    .contains(&status)
    {
        return Err("invalid_output");
    }
    let output_fields = [
        "source_unchanged",
        "stdout_bytes",
        "observed_stdout_bytes",
        "stdout_sha256",
    ];
    let output_count = output_fields
        .iter()
        .filter(|k| row.get(**k).is_some())
        .count();
    if (output_count != 0 && output_count != 4)
        || (["passed", "failed", "source_changed", "output_limit"].contains(&status)
            && output_count != 4)
        || (row.get("exit_code").is_some() && output_count == 0)
    {
        return Err("invalid_output");
    }
    if output_count == 4
        && (!row["stdout_bytes"].as_u64().is_some_and(|n| n <= 65536)
            || !row["observed_stdout_bytes"]
                .as_u64()
                .is_some_and(|n| n <= 67_108_864)
            || !row["source_unchanged"].is_boolean()
            || !row["stdout_sha256"]
                .as_str()
                .is_some_and(|s| s.len() == 64 && s.bytes().all(|b| b.is_ascii_hexdigit()))
            || row
                .get("exit_code")
                .is_some_and(|v| !v.as_u64().is_some_and(|n| n <= 255)))
    {
        return Err("invalid_output");
    }
    if status == "passed"
        && (row["source_unchanged"] != true
            || row["exit_code"].as_u64() != Some(0)
            || row["observed_stdout_bytes"] != row["stdout_bytes"])
    {
        return Err("invalid_output");
    }
    if (status == "failed"
        && (row["source_unchanged"] != true || row["exit_code"].as_u64().is_none_or(|n| n == 0)))
        || (status == "source_changed" && row["source_unchanged"] != false)
        || (status == "output_limit"
            && (row["stdout_bytes"].as_u64() != Some(0)
                || row["observed_stdout_bytes"]
                    .as_u64()
                    .is_none_or(|n| n <= 65536)))
    {
        return Err("invalid_output");
    }
    store.current()?;
    Ok(row)
}

pub(super) fn run(git: &Git<'_>, extra: &str, device: u64, inode: u64) -> Result<Value> {
    if extra.len() > 32768 {
        return Err("invalid_request");
    }
    let request: Value = serde_json::from_str(extra).map_err(|_| "invalid_request")?;
    let (key, deadline) = validate(&request)?;
    let store = match Store::run(git.home, key) {
        Ok(store) => store,
        Err(status) => {
            return Ok(
                json!({"contract":CONTRACT,"key":key,"request_id":request["check"]["request_id"],
            "check_id":request["check"]["check_id"],"input_key":request["check"]["input_key"],
            "candidate_sha":request["check"]["candidate_sha"],"check_sha256":binding(&request["check"]),"status":status,"native_started":false,"cleanup_verified":false}),
            )
        }
    };
    let admission =
        json!({"source":{"path":git.root,"device":device,"inode":inode},"request":request})
            .to_string();
    store.write("admission.json", admission.as_bytes())?;
    let mut launched = false;
    match execute(
        git,
        &request,
        device,
        inode,
        (key, deadline, now()?),
        &store,
        &mut launched,
    ) {
        Ok(row) => Ok(row),
        Err(status) => {
            let clean = !launched
                && status != "cleanup_uncertain"
                && store.current().is_ok()
                && store
                    .read("admission.json", 32768)
                    .is_ok_and(|bytes| bytes == admission.as_bytes());
            let mut row = json!({"contract":CONTRACT,"key":key,"request_id":request["check"]["request_id"],
            "check_id":request["check"]["check_id"],"input_key":request["check"]["input_key"],
            "candidate_sha":request["check"]["candidate_sha"],"check_sha256":binding(&request["check"]),"status":status,"native_started":launched,
            "admission_sha256":initial::digest(admission.as_bytes()),"cleanup_verified":clean});
            if store
                .write("receipt.json", row.to_string().as_bytes())
                .is_err()
                || store.current().is_err()
            {
                row["cleanup_verified"] = json!(false);
            }
            Ok(row)
        }
    }
}

fn execute(
    git: &Git<'_>,
    request: &Value,
    device: u64,
    inode: u64,
    scope: (&str, u64, u64),
    store: &Store,
    launched: &mut bool,
) -> Result<Value> {
    let (key, deadline, wall) = scope;
    git.active()?;
    if !time_valid(now().ok(), wall, deadline) {
        return Err("timeout");
    }
    let (image, kernel, ramdisk) = check_image::verified_files(git.home, &request["image"])?;
    git.active()?;
    let (input, archive) = worktree::check_input_bytes(git, &request["input"], device, inode)?;
    let check = &request["check"];
    if check["input_key"] != input["key"]
        || check["candidate_sha"] != input["candidate_sha"]
        || check["manifest_sha256"] != input["manifest_sha256"]
        || check["image_spec_sha256"] != image["spec_sha256"]
    {
        return Err("invalid_request");
    }
    git.active()?;
    if !time_valid(now().ok(), wall, deadline) {
        return Err("timeout");
    }
    let root = git.home.join("check-runs").join(key);
    let image_store = Store::open(git.home, initial::uuid(&request["image"]["key"])?, false)?;
    store
        .clone_file(&image_store.reader("kernel")?, "kernel")?
        .sync_all()
        .map_err(|_| "image_incomplete")?;
    let ramdisk_file =
        store.clone_file(&image_store.reader("ramdisk.cpio.gz")?, "ramdisk.cpio.gz")?;
    if store.read("kernel", 134_217_728)? != kernel
        || store.read("ramdisk.cpio.gz", 134_217_728)? != ramdisk
    {
        return Err("image_changed");
    }
    image_store.current()?;
    let mut gzip = GzEncoder::new(ramdisk_file, Compression::default());
    gzip.write_all(&archive)
        .and_then(|_| gzip.write_all(&config_archive(check.to_string().as_bytes())))
        .map_err(|_| "image_incomplete")?;
    gzip.finish()
        .and_then(|f| f.sync_all())
        .map_err(|_| "image_incomplete")?;
    let ramdisk = store.read("ramdisk.cpio.gz", 201_326_592)?;
    let scope = json!({"source":{"path":git.root,"device":device,"inode":inode},"request":request})
        .to_string();
    store.write("request.json", scope.as_bytes())?;
    store.write("check.json", check.to_string().as_bytes())?;
    let intent = json!({"contract":CONTRACT,"key":key,"check":check,"deadline_unix_ms":deadline,
        "request_sha256":initial::digest(scope.as_bytes()),"kernel_sha256":initial::digest(&kernel),
        "ramdisk_sha256":initial::digest(&ramdisk),"keeper_sha256":initial::digest(KEEPER)});
    let intent_bytes = intent.to_string();
    let mut keeper = store.create("keeper")?;
    keeper
        .write_all(KEEPER)
        .and_then(|_| keeper.set_permissions(fs::Permissions::from_mode(0o700)))
        .and_then(|_| keeper.sync_all())
        .map_err(|_| "image_incomplete")?;
    let file = store.create("keeper-stdout")?;
    store.write("intent.json", intent_bytes.as_bytes())?;
    store.current()?;
    git.identity(device, inode)?;
    if !time_valid(now().ok(), wall, deadline) {
        return Err("timeout");
    }
    let mut group = Group::new(
        Command::new(root.join("keeper"))
            .arg(&root)
            .env_clear()
            .env("HOME", git.home)
            .env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
            .env("LANG", "C")
            .current_dir(&root)
            .stdin(Stdio::piped())
            .stdout(file.try_clone().map_err(|_| "image_incomplete")?)
            .stderr(Stdio::null())
            .process_group(0)
            .spawn()
            .map_err(|_| "launch_failed")?,
    );
    *launched = true;
    let began = Instant::now();
    let mut pipe = group.0.stdin.take();
    let mut reason = None;
    let mut cancellation = None;
    loop {
        if reason.is_none() {
            reason = git
                .active()
                .err()
                .or_else(|| (!time_valid(now().ok(), wall, deadline)).then_some("timeout"));
            if reason.is_some() {
                pipe.take();
                cancellation = Some(Instant::now());
            }
        }
        if matches!(exited(&group.0), Ok(true)) {
            break;
        }
        if file.metadata().map(|m| m.len() > 8192).unwrap_or(true)
            || cancellation.is_some_and(|t| t.elapsed() >= Duration::from_secs(10))
            || began.elapsed() >= Duration::from_secs(370)
        {
            break;
        }
        thread::sleep(Duration::from_millis(20));
    }
    pipe.take();
    // SAFETY: siginfo_t is a plain C output struct with a valid all-zero representation.
    let mut info: libc::siginfo_t = unsafe { std::mem::zeroed() };
    // SAFETY: this still-owned unreaped child pins its identity through observation and cleanup.
    let exit_ok = unsafe {
        libc::waitid(
            libc::P_PID,
            group.0.id(),
            &mut info,
            libc::WEXITED | libc::WNOHANG | libc::WNOWAIT,
        ) == 0
            && info.si_pid() != 0
            && info.si_code == libc::CLD_EXITED
            && info.si_status() == 0
    };
    let process_closed = group.finish();
    let result = (|| {
        if !process_closed {
            return Err("cleanup_uncertain");
        }
        file.sync_all().map_err(|_| "cleanup_uncertain")?;
        let bytes = store.read("keeper-stdout", 8192)?;
        let mut row = closure(
            store,
            &bytes,
            &intent,
            &initial::digest(intent_bytes.as_bytes()),
        )?;
        let mut output = None;
        if let Some(count) = row["stdout_bytes"].as_u64() {
            let bytes = store.read("output.log", 65536)?;
            if bytes.len() as u64 != count || row["stdout_sha256"] != initial::digest(&bytes) {
                return Err("invalid_output");
            }
            output = Some(bytes);
        }
        if store.read("kernel", 134_217_728)? != kernel
            || store.read("ramdisk.cpio.gz", 201_326_592)? != ramdisk
            || store.read("intent.json", 32768)? != intent_bytes.as_bytes()
            || store.read("request.json", 32768)? != scope.as_bytes()
        {
            return Err("cleanup_uncertain");
        }
        if reason.is_none() {
            reason = git
                .identity(device, inode)
                .err()
                .or_else(|| (!time_valid(now().ok(), wall, deadline)).then_some("timeout"));
        }
        if !exit_ok {
            row["status"] = json!("invalid_output");
        }
        if let Some(status) = reason {
            row["status"] = json!(status);
        }
        row["check_sha256"] = json!(binding(check));
        row["cleanup_verified"] = json!(true);
        attach_feedback(&mut row, request, output.as_deref());
        Ok(row)
    })();
    match result {
        Ok(row) => {
            store.write("receipt.json", row.to_string().as_bytes())?;
            store.current()?;
            Ok(row)
        }
        Err(_) => Ok(
            json!({"contract":CONTRACT,"key":key,"request_id":check["request_id"],"check_id":check["check_id"],
            "input_key":check["input_key"],"candidate_sha":check["candidate_sha"],"check_sha256":binding(check),"status":"cleanup_uncertain","cleanup_verified":false}),
        ),
    }
}
