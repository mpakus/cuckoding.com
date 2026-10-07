//! Fixed read-only app-server inspection. Raw frames never leave this helper.
use crate::probe::{private_directory, Group};
use serde_json::{json, Value};
use std::{
    collections::HashSet,
    io::{self, BufRead, BufReader, Read, Write},
    os::unix::process::CommandExt,
    path::Path,
    process::{ChildStdin, Command, Stdio},
    sync::mpsc::{self, Receiver},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

type Result<T> = std::result::Result<T, &'static str>;
const FRAME_LIMIT: usize = 65_536;

struct Rpc {
    input: ChildStdin,
    output: Receiver<Result<Value>>,
    cancel: Receiver<()>,
    deadline: Instant,
    sequence: u32,
}

impl Rpc {
    fn send(&mut self, value: Value) -> Result<()> {
        writeln!(self.input, "{value}").map_err(|_| "connection_lost")
    }

    fn request(&mut self, method: &str, params: Value) -> Result<Value> {
        self.sequence += 1;
        let id = self.sequence;
        self.send(json!({"id":id,"method":method,"params":params}))?;
        loop {
            if self.cancel.try_recv().is_ok() {
                return Err("cancelled");
            }
            if Instant::now() >= self.deadline {
                return Err("timeout");
            }
            match self.output.recv_timeout(Duration::from_millis(20)) {
                Ok(Ok(message)) => {
                    if message.get("method").is_some() {
                        // A provider request never becomes a host command. Account drift
                        // while fetching a catalog invalidates the observation as well.
                        if message.get("id").is_some() || message["method"] == "account/updated" {
                            return Err("unexpected_message");
                        }
                        continue;
                    }
                    if message["id"].as_u64() != Some(id.into()) {
                        return Err("invalid_output");
                    }
                    if message.get("error").is_some() {
                        return Err("provider_error");
                    }
                    return message
                        .get("result")
                        .filter(|v| v.is_object())
                        .cloned()
                        .ok_or("invalid_output");
                }
                Ok(Err(error)) => return Err(error),
                Err(mpsc::RecvTimeoutError::Disconnected) => return Err("connection_lost"),
                Err(mpsc::RecvTimeoutError::Timeout) => {}
            }
        }
    }
}

fn bounded_frames(reader: impl Read, sender: mpsc::SyncSender<Result<Value>>) {
    let mut reader = BufReader::new(reader);
    let mut total = 0;
    loop {
        let mut bytes = Vec::new();
        let read = (&mut reader)
            .take((FRAME_LIMIT + 1) as u64)
            .read_until(b'\n', &mut bytes);
        total += bytes.len();
        let result = if read.is_err() || bytes.is_empty() {
            Err("connection_lost")
        } else if bytes.len() > FRAME_LIMIT || total > 512 * 1024 || bytes.last() != Some(&b'\n') {
            Err("invalid_output")
        } else {
            serde_json::from_slice::<Value>(&bytes)
                .ok()
                .filter(Value::is_object)
                .ok_or("invalid_output")
        };
        let failed = result.is_err();
        if sender.send(result).is_err() || failed {
            break;
        }
    }
}

fn identifier(value: &Value) -> Result<&str> {
    value
        .as_str()
        .filter(|s| {
            !s.is_empty()
                && s.len() <= 128
                && s.bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"._-/".contains(&b))
        })
        .ok_or("invalid_catalog")
}

fn model(row: &Value) -> Result<Value> {
    let id = identifier(&row["id"])?;
    let name = row["displayName"]
        .as_str()
        .filter(|s| !s.is_empty() && s.len() <= 128 && !s.chars().any(char::is_control))
        .ok_or("invalid_catalog")?;
    let efforts = row["supportedReasoningEfforts"]
        .as_array()
        .filter(|v| v.len() <= 16)
        .ok_or("invalid_catalog")?
        .iter()
        .map(|v| identifier(&v["reasoningEffort"]))
        .collect::<Result<Vec<_>>>()?;
    let default = identifier(&row["defaultReasoningEffort"])?;
    if !efforts.contains(&default) {
        return Err("invalid_catalog");
    }
    let modalities = row
        .get("inputModalities")
        .cloned()
        .unwrap_or(json!(["text", "image"]));
    if !modalities.as_array().is_some_and(|a| {
        a.len() <= 3
            && a.iter()
                .all(|m| matches!(m.as_str(), Some("text" | "image" | "audio")))
    }) {
        return Err("invalid_catalog");
    }
    Ok(
        json!({"id":id,"model":identifier(&row["model"])?,"name":name,"efforts":efforts,
        "default_effort":default,"input_modalities":modalities,"default":row["isDefault"].as_bool().ok_or("invalid_catalog")?}),
    )
}

fn catalog(rpc: &mut Rpc) -> Result<Vec<Value>> {
    let mut models = Vec::new();
    let mut cursor = Value::Null;
    let mut seen = HashSet::new();
    let mut ids = HashSet::new();
    for _ in 0..4 {
        let result = rpc.request(
            "model/list",
            json!({"limit":32,"includeHidden":false,"cursor":cursor}),
        )?;
        for row in result["data"]
            .as_array()
            .filter(|r| r.len() <= 32)
            .ok_or("invalid_catalog")?
        {
            if row["hidden"] != false {
                return Err("invalid_catalog");
            }
            let entry = model(row)?;
            if !ids.insert(entry["id"].as_str().unwrap().to_owned()) {
                return Err("invalid_catalog");
            }
            models.push(entry);
        }
        cursor = result["nextCursor"].clone();
        if cursor.is_null() {
            return Ok(models);
        }
        let next = cursor
            .as_str()
            .filter(|v| !v.is_empty() && v.len() <= 1024)
            .ok_or("invalid_catalog")?;
        if !seen.insert(next.to_owned()) {
            return Err("invalid_catalog");
        }
    }
    Err("invalid_catalog")
}

fn inspect(rpc: &mut Rpc, directory: &Path) -> Result<Value> {
    let init = rpc.request(
        "initialize",
        json!({"clientInfo":{"name":"cuckoding","title":"Cuckoding","version":"0.1.0"}}),
    )?;
    if init["codexHome"].as_str() != directory.to_str() {
        return Err("profile_mismatch");
    }
    rpc.send(json!({"method":"initialized","params":{}}))?;
    let config = rpc.request("config/read", json!({"includeLayers":false}))?;
    if config["config"]["cli_auth_credentials_store"] != "file"
        || config["config"]["model_provider"] != "openai"
    {
        return Err("unsupported_profile");
    }
    let account = rpc.request("account/read", json!({"refreshToken":false}))?;
    if !account["requiresOpenaiAuth"].is_boolean() {
        return Err("invalid_output");
    }
    if account["account"].is_null() {
        return Ok(
            json!({"status":"checked","authorization":"not_connected","catalog_status":"not_requested"}),
        );
    }
    if account["account"]["type"] != "chatgpt" {
        return Ok(
            json!({"status":"checked","authorization":"unsupported_account","catalog_status":"not_requested"}),
        );
    }
    // Account observation remains intact if only model discovery fails.
    match catalog(rpc) {
        Ok(models) => Ok(
            json!({"status":"checked","authorization":"chatgpt","catalog_status":"fresh","models":models}),
        ),
        Err(error) => Ok(
            json!({"status":"checked","authorization":"chatgpt","catalog_status":"failed","catalog_error":error}),
        ),
    }
}

fn profile(directory: &Path) -> Result<()> {
    private_directory(directory).map_err(|_| "unsafe_profile")?;
    let mut pending = vec![directory.to_path_buf()];
    let mut count = 0;
    // Metadata only. Bounded traversal also rejects redirected caches/SQLite files.
    while let Some(path) = pending.pop() {
        for entry in std::fs::read_dir(path).map_err(|_| "unsafe_profile")? {
            let entry = entry.map_err(|_| "unsafe_profile")?;
            count += 1;
            if count > 4096 {
                return Err("unsafe_profile");
            }
            let kind = entry.file_type().map_err(|_| "unsafe_profile")?;
            if kind.is_dir() {
                pending.push(entry.path());
            } else if !kind.is_file() {
                return Err("unsafe_profile");
            }
        }
    }
    Ok(())
}

fn run(path: &Path, directory: &Path, cancel: Receiver<()>, limit: Duration) -> Result<Value> {
    profile(directory)?;
    let executable = std::fs::canonicalize(path).map_err(|_| "launch_failed")?;
    if !path.is_absolute() {
        return Err("launch_failed");
    }
    let started = Instant::now();
    let spawned_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| "launch_failed")?
        .as_millis();
    let mut group = Group(
        Command::new(executable)
            .args([
                "app-server",
                "--listen",
                "stdio://",
                "-c",
                "cli_auth_credentials_store=\"file\"",
                "-c",
                "model_provider=\"openai\"",
                "-c",
                "sandbox_mode=\"read-only\"",
                "-c",
                "approval_policy=\"never\"",
            ])
            .env_clear()
            .env("HOME", directory)
            .env("CODEX_HOME", directory)
            .env("TMPDIR", directory)
            .env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
            .env("LANG", "en_US.UTF-8")
            .env("TZ", "UTC")
            .current_dir(directory)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .process_group(0)
            .spawn()
            .map_err(|_| "launch_failed")?,
    );
    let pid = group.0.id();
    let input = group.0.stdin.take().ok_or("launch_failed")?;
    let stdout = group.0.stdout.take().ok_or("launch_failed")?;
    let (sender, output) = mpsc::sync_channel(1);
    thread::spawn(move || bounded_frames(stdout, sender));
    let mut rpc = Rpc {
        input,
        output,
        cancel,
        deadline: started + limit,
        sequence: 0,
    };
    let mut result = inspect(&mut rpc, directory).unwrap_or_else(|error| json!({"status":error}));
    drop(rpc);
    drop(group);
    result["pid"] = json!(pid);
    result["spawned_at_ms"] = json!(spawned_at);
    result["elapsed_ms"] = json!(started.elapsed().as_millis());
    Ok(result)
}

pub fn main(args: &[String]) {
    let (sender, cancel) = mpsc::channel();
    thread::spawn(move || {
        let _ = io::stdin().read(&mut [0]);
        let _ = sender.send(());
    });
    let result = match args {
        [path, directory] => run(
            Path::new(path),
            Path::new(directory),
            cancel,
            Duration::from_secs(10),
        ),
        _ => Err("launch_failed"),
    };
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
        fs,
        os::unix::fs::PermissionsExt,
        path::PathBuf,
        sync::atomic::{AtomicUsize, Ordering},
    };
    static SERIAL: AtomicUsize = AtomicUsize::new(0);

    fn fixture(account: Value, models: Value) -> (PathBuf, PathBuf) {
        let dir = PathBuf::from(format!(
            "/private/tmp/cuckoding-connection-{}-{}",
            std::process::id(),
            SERIAL.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&dir).unwrap();
        fs::set_permissions(&dir, fs::Permissions::from_mode(0o700)).unwrap();
        let path = dir.join("codex");
        let init = json!({"id":1,"result":{"codexHome":dir,"userAgent":"fixture-secret"}});
        let config = json!({"id":2,"result":{"config":{"cli_auth_credentials_store":"file","model_provider":"openai","ignored":"fixture-secret"}}});
        let account = json!({"id":3,"result":{"account":account,"requiresOpenaiAuth":true}});
        let first = json!({"id":4,"result":{"data":models,"nextCursor":"next"}});
        let second = json!({"id":5,"result":{"data":[],"nextCursor":null}});
        fs::write(
            &path,
            format!(
                r#"#!/bin/sh
test -z "$CCODING_CONNECTION_CANARY" || exit 1
test "$HOME" = "$PWD" || exit 2
test "$CODEX_HOME" = "$PWD" || exit 3
test "$1" = app-server || exit 4
while IFS= read -r line; do
  case "$line" in
    *'"method":"initialize"'*) printf '%s\n' '{init}' ;;
    *'"method":"config/read"'*) printf '%s\n' '{config}' ;;
    *'"method":"account/read"'*) printf '%s\n' '{account}' ;;
    *'"cursor":"next"'*) printf '%s\n' '{second}' ;;
    *'"method":"model/list"'*) printf '%s\n' '{first}' ;;
    *'"method":"initialized"'*) : ;;
    *) exit 9 ;;
  esac
done
"#
            ),
        )
        .unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
        (dir, path)
    }

    fn sample() -> Value {
        json!({"id":"test-model","model":"test-model","displayName":"Test model","hidden":false,"isDefault":true,"defaultReasoningEffort":"medium","supportedReasoningEfforts":[{"reasoningEffort":"medium","description":"fixture-secret"}],"inputModalities":["text"],"unknown":"fixture-secret"})
    }

    fn check(path: &Path, dir: &Path) -> Value {
        let (_sender, cancel) = mpsc::channel();
        run(path, dir, cancel, Duration::from_secs(2)).unwrap()
    }

    #[test]
    fn private_inspection_paginates_and_drops_raw_account_and_model_fields() {
        std::env::set_var("CCODING_CONNECTION_CANARY", "fixture-secret");
        let (dir, path) = fixture(
            json!({"type":"chatgpt","email":"fixture-secret","planType":"fixture-secret"}),
            json!([sample()]),
        );
        let result = check(&path, &dir);
        assert_eq!(result["status"], "checked");
        assert_eq!(result["authorization"], "chatgpt");
        assert_eq!(result["catalog_status"], "fresh");
        assert_eq!(result["models"].as_array().unwrap().len(), 1);
        assert_eq!(result["models"][0]["efforts"], json!(["medium"]));
        assert!(!result.to_string().contains("fixture-secret"));
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn absent_and_unsupported_accounts_do_not_fetch_models() {
        for (account, expected) in [
            (Value::Null, "not_connected"),
            (json!({"type":"apiKey"}), "unsupported_account"),
        ] {
            let (dir, path) = fixture(account, json!(["invalid models must never be requested"]));
            let result = check(&path, &dir);
            assert_eq!(result["authorization"], expected);
            assert_eq!(result["catalog_status"], "not_requested");
            assert!(result["models"].is_null());
            fs::remove_dir_all(dir).unwrap();
        }
    }

    #[test]
    fn profile_configuration_and_pagination_drift_fail_closed() {
        for (from, to, field, expected) in [
            ("codexHome", "wrongHome", "status", "profile_mismatch"),
            (
                "\"cli_auth_credentials_store\":\"file\"",
                "\"cli_auth_credentials_store\":\"keyring\"",
                "status",
                "unsupported_profile",
            ),
            (
                "\"nextCursor\":null",
                "\"nextCursor\":\"next\"",
                "catalog_status",
                "failed",
            ),
        ] {
            let (dir, path) = fixture(json!({"type":"chatgpt"}), json!([sample()]));
            let script = fs::read_to_string(&path).unwrap();
            assert!(script.contains(from));
            fs::write(&path, script.replace(from, to)).unwrap();
            let result = check(&path, &dir);
            assert_eq!(result[field], expected);
            assert!(result["models"].is_null());
            fs::remove_dir_all(dir).unwrap();
        }
    }

    #[test]
    fn malformed_models_preserve_auth_and_never_publish_partial_catalogs() {
        for rows in [
            json!([{"id":"fixture-secret"}]),
            json!([sample(), sample()]),
            json!([{"hidden":true}]),
        ] {
            let (dir, path) = fixture(json!({"type":"chatgpt"}), rows);
            let result = check(&path, &dir);
            assert_eq!(result["authorization"], "chatgpt");
            assert_eq!(result["catalog_status"], "failed");
            assert!(result["models"].is_null());
            assert!(!result.to_string().contains("fixture-secret"));
            fs::remove_dir_all(dir).unwrap();
        }
    }

    #[test]
    fn frames_are_bounded_and_never_forward_server_requests_or_errors() {
        for (body,status) in [
            ("printf '%s\\n' '{\"id\":1,\"method\":\"command/exec\",\"params\":{\"secret\":\"fixture-secret\"}}'".to_owned(),"unexpected_message"),
            ("printf '%s\\n' '{\"id\":1,\"error\":{\"message\":\"fixture-secret\"}}'".to_owned(),"provider_error"),
            ("head -c 70000 /dev/zero".to_owned(),"invalid_output"),
            ("printf 'fixture-secret\\n'".to_owned(),"invalid_output"),
        ] {
            let (dir,path)=fixture(Value::Null,json!([]));
            fs::write(&path,format!("#!/bin/sh\n{body}\nsleep 10\n")).unwrap();
            let result=check(&path,&dir);
            assert_eq!(result["status"],status);
            assert!(!result.to_string().contains("fixture-secret"));
            fs::remove_dir_all(dir).unwrap();
        }
        let (sender, receiver) = mpsc::sync_channel(1);
        thread::spawn(move || bounded_frames(&b"{\"id\":1,\"result\":{}}\n"[..], sender));
        assert_eq!(receiver.recv().unwrap().unwrap()["id"], 1);
    }

    #[test]
    fn cancellation_timeout_and_unsafe_profile_fail_closed() {
        let mut peer = Command::new("/bin/sleep").arg("30").spawn().unwrap();
        for cancelled in [false, true] {
            let (dir, path) = fixture(Value::Null, json!([]));
            fs::write(
                &path,
                "#!/bin/sh\ntrap '' TERM\nsleep 30 &\necho $! > child\nwait\n",
            )
            .unwrap();
            let (sender, cancel) = mpsc::channel();
            if cancelled {
                thread::spawn(move || {
                    thread::sleep(Duration::from_millis(100));
                    sender.send(()).unwrap();
                });
            }
            let result = run(&path, &dir, cancel, Duration::from_millis(250)).unwrap();
            assert_eq!(
                result["status"],
                if cancelled { "cancelled" } else { "timeout" }
            );
            let child = fs::read_to_string(dir.join("child"))
                .unwrap()
                .trim()
                .parse::<i32>()
                .unwrap();
            thread::sleep(Duration::from_millis(100));
            assert_eq!(unsafe { libc::kill(child, 0) }, -1);
            assert!(peer.try_wait().unwrap().is_none());
            std::os::unix::fs::symlink(&path, dir.join("auth.json")).unwrap();
            let (_sender, cancel) = mpsc::channel();
            assert_eq!(
                run(&path, &dir, cancel, Duration::from_secs(1)).unwrap_err(),
                "unsafe_profile"
            );
            fs::remove_dir_all(dir).unwrap();
        }
        peer.kill().unwrap();
        peer.wait().unwrap();
    }
}
