//! Cursor's fixed setup CLI, with isolated file credentials and no inference commands.
use crate::{
    connection::profile_lock,
    probe::{exited, Group},
};
use serde_json::{json, Value};
use std::{
    cell::Cell,
    collections::HashSet,
    fs,
    io::{self, Read, Write},
    os::unix::process::CommandExt,
    path::Path,
    process::{Command, Stdio},
    sync::mpsc::{self, Receiver},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

type Result<T> = std::result::Result<T, &'static str>;
#[derive(Clone, Copy, PartialEq)]
pub enum Operation {
    Probe,
    Inspect,
    Login,
    Logout,
}

fn login_url(text: &str) -> Option<&str> {
    text.split_whitespace().find(|candidate| {
        let Ok(url) = tauri::Url::parse(candidate) else {
            return false;
        };
        url.scheme() == "https"
            && url.host_str() == Some("cursor.com")
            && url.path() == "/loginDeepControl"
            && url.port_or_known_default() == Some(443)
            && url.username().is_empty()
            && url.password().is_none()
            && url.fragment().is_none()
            && !candidate.contains('\\')
            && candidate.len() <= 8192
    })
}

fn identifier(text: &str) -> bool {
    !text.is_empty()
        && text.len() <= 128
        && text
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"._/-".contains(&b))
}

fn models(bytes: &[u8]) -> Result<Value> {
    let text = std::str::from_utf8(bytes).map_err(|_| "invalid_output")?;
    if text.trim() == "No models available for this account." {
        return Ok(json!([]));
    }
    let mut lines = text.lines().filter(|line| !line.trim().is_empty());
    if lines.next() != Some("Available models") {
        return Err("invalid_output");
    }
    let mut rows = Vec::new();
    let mut ids = HashSet::new();
    let mut footer = false;
    for line in lines {
        if line.starts_with("Tip: use --model <id> (or /model <id>") {
            if footer {
                return Err("invalid_output");
            }
            footer = true;
            continue;
        }
        if footer || rows.len() >= 128 {
            return Err("invalid_output");
        }
        let (line, default) = if let Some(row) = line.strip_suffix(" (current, default)") {
            (row, true)
        } else if let Some(row) = line.strip_suffix(" (default)") {
            (row, true)
        } else {
            (line.strip_suffix(" (current)").unwrap_or(line), false)
        };
        let (id, name) = line.split_once(" - ").unwrap_or((line, line));
        if !identifier(id)
            || !ids.insert(id.to_owned())
            || name.is_empty()
            || name.len() > 128
            || name.chars().any(char::is_control)
        {
            return Err("invalid_output");
        }
        rows.push(json!({"id":id,"model":id,"name":name,"default":default,"hidden":false}));
    }
    if !footer || rows.is_empty() {
        return Err("invalid_output");
    }
    Ok(json!(rows))
}

fn authenticated(bytes: &[u8]) -> Result<bool> {
    let result: Value = serde_json::from_slice(bytes).map_err(|_| "invalid_output")?;
    match (
        result["status"].as_str(),
        result["isAuthenticated"].as_bool(),
    ) {
        (Some("authenticated"), Some(true)) => Ok(true),
        (Some("unauthenticated" | "partially-authenticated"), Some(false)) => Ok(false),
        _ => Err("invalid_output"),
    }
}

struct Cli<'a> {
    path: &'a Path,
    directory: &'a Path,
    cancel: Receiver<()>,
    deadline: Instant,
    wall: SystemTime,
    pid: Cell<u32>,
}
impl Cli<'_> {
    fn call(
        &self,
        args: &[&str],
        login: bool,
        progress: &mut impl FnMut(&str) -> Result<()>,
    ) -> Result<Vec<u8>> {
        let executable = fs::canonicalize(self.path).map_err(|_| "launch_failed")?;
        if !self.path.is_absolute() || !executable.is_file() {
            return Err("launch_failed");
        }
        let mut group = Group(
            Command::new(executable)
                .args(args)
                .env_clear()
                .env("HOME", self.directory)
                .env("CURSOR_CONFIG_DIR", self.directory)
                .env("CURSOR_DATA_DIR", self.directory)
                .env("TMPDIR", self.directory)
                .env("AGENT_CLI_CREDENTIAL_STORE", "file")
                .env("NO_OPEN_BROWSER", "1")
                .env("DIRENV_DISABLE", "1")
                .env("CURSOR_AGENT_DISABLE_DEBUG_LOG", "1")
                .env("NO_COLOR", "1")
                .env("TERM", "dumb")
                .env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
                .env("LANG", "en_US.UTF-8")
                .current_dir(self.directory)
                .stdin(Stdio::null())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .process_group(0)
                .spawn()
                .map_err(|_| "launch_failed")?,
        );
        self.pid.set(group.0.id());
        let mut stdout = group.0.stdout.take().ok_or("connection_lost")?;
        let (sender, output) = mpsc::sync_channel(8);
        thread::spawn(move || loop {
            let mut bytes = [0; 4096];
            match stdout.read(&mut bytes) {
                Ok(0) => break,
                Ok(n) => {
                    if sender.send(Ok(bytes[..n].to_vec())).is_err() {
                        break;
                    }
                }
                Err(_) => {
                    let _ = sender.send(Err("connection_lost"));
                    break;
                }
            }
        });
        let mut bytes = Vec::new();
        let mut prompted = false;
        loop {
            if self.cancel.try_recv().is_ok() {
                return Err("cancelled");
            }
            if Instant::now() >= self.deadline || SystemTime::now() >= self.wall {
                return Err("timeout");
            }
            match output.recv_timeout(Duration::from_millis(20)) {
                Ok(chunk) => {
                    bytes.extend(chunk?);
                    if bytes.len() > 65_536 {
                        return Err("invalid_output");
                    }
                    if login && !prompted {
                        // Wait for the line ending so a split URL cannot be published truncated.
                        if let Some(end) = bytes.iter().rposition(|b| *b == b'\n') {
                            if let Some(url) = login_url(
                                std::str::from_utf8(&bytes[..end]).map_err(|_| "invalid_output")?,
                            ) {
                                progress(url)?;
                                prompted = true;
                            }
                        }
                    }
                }
                Err(mpsc::RecvTimeoutError::Disconnected)
                    if exited(&group.0).map_err(|_| "connection_lost")? =>
                {
                    break
                }
                Err(_) => {}
            }
        }
        let mut info: libc::siginfo_t = unsafe { std::mem::zeroed() };
        let success = unsafe {
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
        drop(group);
        if success {
            Ok(bytes)
        } else {
            Err("provider_error")
        }
    }
}

fn run(
    path: &Path,
    directory: &Path,
    operation: Operation,
    cancel: Receiver<()>,
    limit: Duration,
    progress: &mut impl FnMut(&str) -> Result<()>,
) -> Result<Value> {
    let _lock = profile_lock(directory)?;
    let started = Instant::now();
    let spawned = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| "launch_failed")?
        .as_millis();
    let cli = Cli {
        path,
        directory,
        cancel,
        deadline: started + limit,
        wall: SystemTime::now() + limit,
        pid: Cell::new(0),
    };
    let result = (|| {
        if operation == Operation::Probe {
            let bytes = cli.call(&["--version"], false, progress)?;
            let version = std::str::from_utf8(&bytes)
                .map_err(|_| "invalid_output")?
                .trim();
            if version.len() != 18
                || !version
                    .bytes()
                    .all(|b| b.is_ascii_hexdigit() || b".-".contains(&b))
            {
                return Err("invalid_output");
            }
            return Ok(json!({"status":"observed","version":version}));
        }
        if operation == Operation::Login {
            cli.call(&["login"], true, progress)?;
        }
        if operation == Operation::Logout {
            cli.call(&["logout"], false, progress)?;
        }
        let signed_in =
            authenticated(&cli.call(&["status", "--format", "json"], false, progress)?)?;
        if operation == Operation::Login && !signed_in {
            return Err("login_failed");
        }
        if operation == Operation::Logout && signed_in {
            return Err("logout_unconfirmed");
        }
        if !signed_in {
            return Ok(
                json!({"status":"checked","authorization":"not_connected","catalog_status":"not_requested"}),
            );
        }
        match cli
            .call(&["models"], false, progress)
            .and_then(|bytes| models(&bytes))
        {
            Ok(rows) => Ok(
                json!({"status":"checked","authorization":"cursor","catalog_status":"fresh","models":rows}),
            ),
            Err("cancelled") => Err("cancelled"),
            Err(_) => {
                Ok(json!({"status":"checked","authorization":"cursor","catalog_status":"failed"}))
            }
        }
    })();
    let mut result = result.unwrap_or_else(|status| json!({"status":status}));
    if cli.pid.get() != 0 {
        result["pid"] = json!(cli.pid.get());
    }
    result["spawned_at_ms"] = json!(spawned);
    result["elapsed_ms"] = json!(started.elapsed().as_millis());
    Ok(result)
}

pub fn main(args: &[String], operation: Operation) {
    let (sender, cancel) = mpsc::channel();
    thread::spawn(move || {
        let _ = io::stdin().read(&mut [0]);
        let _ = sender.send(());
    });
    let result = match args {
        [path, directory] => run(
            Path::new(path),
            Path::new(directory),
            operation,
            cancel,
            Duration::from_secs(if operation == Operation::Login {
                600
            } else if operation == Operation::Probe {
                5
            } else {
                15
            }),
            &mut |url| {
                writeln!(
                    io::stdout(),
                    "{}",
                    json!({"status":"awaiting_login","auth_url":url})
                )
                .map_err(|_| "connection_lost")
            },
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
        os::unix::fs::PermissionsExt,
        sync::atomic::{AtomicUsize, Ordering},
    };
    static SERIAL: AtomicUsize = AtomicUsize::new(0);

    fn fixture(body: &str) -> (std::path::PathBuf, std::path::PathBuf) {
        let dir = std::path::PathBuf::from(format!(
            "/private/tmp/cuckoding-cursor-{}-{}",
            std::process::id(),
            SERIAL.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&dir).unwrap();
        fs::set_permissions(&dir, fs::Permissions::from_mode(0o700)).unwrap();
        let path = dir.join("agent");
        fs::write(&path, format!("#!/bin/sh\n{body}\n")).unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
        (dir, path)
    }

    #[test]
    fn catalog_is_bounded_complete_and_never_invents_models() {
        let rows = models(b"Available models\n\ngrok-fixture - Grok (current)\ngpt-fixture - GPT (default)\n\nTip: use --model <id> (or /model <id> in interactive mode) to switch.\n").unwrap();
        assert_eq!(rows[0]["id"], "grok-fixture");
        assert_eq!(rows[1]["default"], true);
        assert!(models(b"Available models\ngrok - Grok\n").is_err());
        assert!(models(b"Available models\ngrok - Grok\ngrok - Duplicate\nTip: use --model <id> (or /model <id>\n").is_err());
        assert!(models(
            b"Available models\ngrok - Bad\x1bsecret\nTip: use --model <id> (or /model <id>\n"
        )
        .is_err());
        assert_eq!(
            models(b"No models available for this account.\n").unwrap(),
            json!([])
        );
        assert!(!authenticated(
            br#"{"status":"unauthenticated","isAuthenticated":false,"message":"secret"}"#
        )
        .unwrap());
        assert!(authenticated(br#"{"status":"authenticated","isAuthenticated":false}"#).is_err());
        assert!(login_url("https://cursor.com/loginDeepControl?uuid=fixture").is_some());
        assert!(login_url("https://cursor.com.evil.test/loginDeepControl").is_none());
        assert!(login_url("https://user@cursor.com/loginDeepControl").is_none());
    }

    #[test]
    fn private_file_credentials_clean_environment_and_public_catalog_only() {
        std::env::set_var("CUCKODING_CURSOR_CANARY", "secret-canary");
        let (dir, path) = fixture(
            r#"
test -z "$CUCKODING_CURSOR_CANARY" || exit 1
test "$HOME" = "$PWD" || exit 2
test "$CURSOR_CONFIG_DIR" = "$PWD" || exit 3
test "$CURSOR_DATA_DIR" = "$PWD" || exit 4
test "$AGENT_CLI_CREDENTIAL_STORE" = file || exit 5
test "$NO_OPEN_BROWSER" = 1 || exit 6
test "$DIRENV_DISABLE" = 1 || exit 7
test "$CURSOR_AGENT_DISABLE_DEBUG_LOG" = 1 || exit 8
case "$1" in
status) printf '%s\n' '{"status":"authenticated","isAuthenticated":true,"userInfo":{"email":"secret-canary"}}';;
models) printf 'Available models\n\ngrok-fixture - Grok (default)\n\nTip: use --model <id> (or /model <id> in interactive mode) to switch.\n';;
*) exit 8;;
esac
"#,
        );
        let (_sender, cancel) = mpsc::channel();
        let result = run(
            &path,
            &dir,
            Operation::Inspect,
            cancel,
            Duration::from_secs(3),
            &mut |_| panic!("no login"),
        )
        .unwrap();
        assert_eq!(result["authorization"], "cursor");
        assert_eq!(result["models"][0]["id"], "grok-fixture");
        assert!(!result.to_string().contains("secret-canary"));
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn signout_verifies_and_partial_catalog_failure_is_not_a_fresh_list() {
        for (body, operation, status) in [
            ("echo '{\"status\":\"authenticated\",\"isAuthenticated\":true}'", Operation::Logout, "logout_unconfirmed"),
            ("case \"$1\" in status) echo '{\"status\":\"authenticated\",\"isAuthenticated\":true}';; models) echo secret; exit 1;; esac", Operation::Inspect, "checked"),
        ] {
            let (dir, path) = fixture(body);
            let (_sender, cancel) = mpsc::channel();
            let result = run(&path, &dir, operation, cancel, Duration::from_secs(3), &mut |_| Ok(())).unwrap();
            assert_eq!(result["status"], status);
            assert!(result["models"].is_null());
            if operation == Operation::Inspect { assert_eq!(result["catalog_status"], "failed"); }
            fs::remove_dir_all(dir).unwrap();
        }
    }

    #[test]
    fn login_link_is_transient_and_cancel_timeout_stop_owned_descendants() {
        for cancel_login in [true, false] {
            let (dir, path) = fixture("trap '' TERM\nsleep 30 &\necho $! > child\nprintf 'Open https://cursor.com/loginDeepControl?uuid=fixture\\n'\nwait");
            let (sender, cancel) = mpsc::channel();
            let mut prompted = false;
            let result = run(
                &path,
                &dir,
                Operation::Login,
                cancel,
                Duration::from_secs(2),
                &mut |url| {
                    assert!(url.starts_with("https://cursor.com/loginDeepControl?"));
                    prompted = true;
                    if cancel_login {
                        sender.send(()).unwrap();
                    }
                    Ok(())
                },
            )
            .unwrap();
            assert!(prompted, "{result}");
            assert_eq!(
                result["status"],
                if cancel_login { "cancelled" } else { "timeout" }
            );
            assert!(!result.to_string().contains("uuid"));
            let child: i32 = fs::read_to_string(dir.join("child"))
                .unwrap()
                .trim()
                .parse()
                .unwrap();
            thread::sleep(Duration::from_millis(100));
            assert_eq!(unsafe { libc::kill(child, 0) }, -1);
            fs::remove_dir_all(dir).unwrap();
        }
    }
}
