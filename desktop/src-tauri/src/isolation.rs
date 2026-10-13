//! Fixed Codex sandbox canaries. No account, inference, Arena or arbitrary command input.
use crate::probe::{exited, private_directory, Group};
use serde_json::{json, Value};
use std::{
    fs,
    io::{self, Read, Write},
    net::{TcpListener, TcpStream},
    os::unix::{fs::DirBuilderExt, process::CommandExt},
    path::Path,
    process::{Command, Stdio},
    sync::mpsc::{self, Receiver},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

const VERSION: &str = "0.162.0-alpha.17.2";
const CONTRACT: &str = "codex-isolation-v1";
type Result<T> = std::result::Result<T, &'static str>;

// Deliberately fixed commands: user/provider text never becomes shell syntax.
// Checking one positive read with the same tool prevents a missing tool from
// appearing to pass every negative read. Raw output never leaves the helper.
const SCRIPT: &str = r#"
set -eu
test "${CUCKODING_ISOLATION_CANARY+x}" != x
/usr/bin/curl --version >/dev/null
test "$(/bin/cat source.txt)" = CC_SOURCE
if test "$1" = write; then
  printf CC_WRITTEN > result.txt
else
  if /usr/bin/touch forbidden.txt 2>/dev/null; then exit 11; fi
fi
for target in ../outside.txt ../profile/canary ../scratch/canary ../$2/source.txt link .git .cuckoding/canary; do
  if /bin/cat "$target" >/dev/null 2>&1; then exit 12; fi
done
for target in ../outside-new ../profile/new ../scratch/new ../$2/new .git .cuckoding/new; do
  if /usr/bin/touch "$target" >/dev/null 2>&1; then exit 13; fi
done
if test "$1" = write; then
  if /bin/ln ../outside.txt hardlink 2>/dev/null; then exit 14; fi
  if /bin/mv .cuckoding moved-policy 2>/dev/null; then exit 15; fi
fi
/usr/bin/curl --silent --max-time 1 --noproxy '*' "$3" >/dev/null 2>&1 || true
printf CC_ISOLATED
"#;

fn policy(workspace: &Path, profile: &Path, mode: &str) -> Result<String> {
    let path = |p: &Path| p.to_str().map(str::to_owned).ok_or("unsafe_fixture");
    let entries = [
        (":root".into(), "deny"),
        (":minimal".into(), "read"),
        (":tmpdir".into(), "deny"),
        (":slash_tmp".into(), "deny"),
        (path(profile)?, "deny"),
        (path(workspace)?, mode),
        (path(&workspace.join(".git"))?, "deny"),
        (path(&workspace.join(".cuckoding"))?, "deny"),
    ];
    let rules = entries
        .iter()
        .map(|(path, access)| format!("{}=\"{access}\"", json!(path)))
        .collect::<Vec<_>>()
        .join(",");
    Ok(format!(
        "permissions.cuckoding-isolation={{filesystem={{{rules}}},network={{enabled=false}}}}"
    ))
}

struct Runner<'a> {
    executable: &'a Path,
    root: &'a Path,
    cancel: Receiver<()>,
    started: Instant,
    wall_started: SystemTime,
    limit: Duration,
    children: Vec<Value>,
}

impl Runner<'_> {
    fn active(&self) -> Result<()> {
        if self.cancel.try_recv().is_ok() {
            return Err("cancelled");
        }
        if self.started.elapsed() >= self.limit
            || self.wall_started.elapsed().unwrap_or(self.limit) >= self.limit
        {
            return Err("timeout");
        }
        Ok(())
    }

    fn command(&mut self, args: &[&str], cwd: &Path) -> Result<Vec<u8>> {
        self.active()?;
        let profile = self.root.join("profile");
        let mut child = Command::new(self.executable);
        child
            .args(args)
            .env_clear()
            .env("HOME", &profile)
            .env("CODEX_HOME", &profile)
            .env("TMPDIR", self.root.join("scratch"))
            .env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
            .env("LANG", "en_US.UTF-8")
            .env("TZ", "UTC")
            .current_dir(cwd)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .process_group(0);
        let mut group = Group(child.spawn().map_err(|_| "launch_failed")?);
        self.children
            .push(json!({"pid":group.0.id(), "spawned_at_ms":SystemTime::now()
            .duration_since(UNIX_EPOCH).map_err(|_| "launch_failed")?.as_millis()}));
        let stdout = group.0.stdout.take().ok_or("launch_failed")?;
        let (sender, output) = mpsc::sync_channel(1);
        thread::spawn(move || {
            let mut bytes = Vec::new();
            let result = stdout.take(129).read_to_end(&mut bytes);
            let _ = sender.send(result.map(|_| bytes));
        });
        let mut bytes = None;
        loop {
            self.active()?;
            if let Ok(result) = output.try_recv() {
                let value = result.map_err(|_| "invalid_output")?;
                if value.len() > 128 {
                    return Err("invalid_output");
                }
                bytes = Some(value);
            }
            if let (true, Some(bytes)) = (exited(&group.0).map_err(|_| "launch_failed")?, &bytes) {
                // Keep the leader unreaped until Group kills its descendants.
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
                return if success {
                    Ok(bytes.clone())
                } else {
                    Err("isolation_failed")
                };
            }
            thread::sleep(Duration::from_millis(10));
        }
    }

    fn accept_control(&self, listener: &TcpListener) -> Result<()> {
        // A completed client connect need not already be visible to nonblocking
        // accept. Keep this positive control inside the same cancellation/deadline.
        loop {
            self.active()?;
            match listener.accept() {
                Ok(connection) => {
                    drop(connection);
                    return Ok(());
                }
                Err(e)
                    if matches!(
                        e.kind(),
                        io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
                    ) =>
                {
                    thread::sleep(Duration::from_millis(10))
                }
                Err(_) => return Err("network_unavailable"),
            }
        }
    }

    fn check(&mut self) -> Result<()> {
        self.active()?;
        private_directory(self.root).map_err(|_| "unsafe_fixture")?;
        if fs::read_dir(self.root)
            .map_err(|_| "unsafe_fixture")?
            .next()
            .is_some()
        {
            return Err("unsafe_fixture");
        }
        for name in [
            "profile",
            "scratch",
            "first",
            "second",
            "first/.cuckoding",
            "second/.cuckoding",
        ] {
            fs::DirBuilder::new()
                .mode(0o700)
                .create(self.root.join(name))
                .map_err(|_| "unsafe_fixture")?;
        }
        for name in [
            "outside.txt",
            "profile/canary",
            "scratch/canary",
            "first/.git",
            "second/.git",
            "first/.cuckoding/canary",
            "second/.cuckoding/canary",
        ] {
            fs::write(self.root.join(name), b"CC_PRIVATE").map_err(|_| "unsafe_fixture")?;
        }
        for name in ["first", "second"] {
            let workspace = self.root.join(name);
            fs::write(workspace.join("source.txt"), b"CC_SOURCE").map_err(|_| "unsafe_fixture")?;
            std::os::unix::fs::symlink(self.root.join("outside.txt"), workspace.join("link"))
                .map_err(|_| "unsafe_fixture")?;
        }
        if self.command(&["--version"], self.root)? != format!("codex-cli {VERSION}\n").as_bytes() {
            return Err("unsupported_version");
        }
        let listener = TcpListener::bind("127.0.0.1:0").map_err(|_| "network_unavailable")?;
        listener
            .set_nonblocking(true)
            .map_err(|_| "network_unavailable")?;
        let addr = listener.local_addr().map_err(|_| "network_unavailable")?;
        // Prove the local endpoint is reachable outside the sandbox first.
        let control = TcpStream::connect(addr).map_err(|_| "network_unavailable")?;
        self.accept_control(&listener)?;
        drop(control);
        let url = format!("http://{addr}/");
        for (name, sibling) in [("first", "second"), ("second", "first")] {
            let workspace = self.root.join(name);
            for mode in ["read", "write"] {
                let profile = policy(&workspace, &self.root.join("profile"), mode)?;
                let output = self.command(
                    &[
                        "sandbox",
                        "-P",
                        "cuckoding-isolation",
                        "-C",
                        workspace.to_str().ok_or("unsafe_fixture")?,
                        "-c",
                        &profile,
                        "--",
                        "/bin/sh",
                        "-c",
                        SCRIPT,
                        "cuckoding-isolation",
                        mode,
                        sibling,
                        &url,
                    ],
                    &workspace,
                )?;
                if output != b"CC_ISOLATED"
                    || !matches!(listener.accept(), Err(e) if e.kind() == io::ErrorKind::WouldBlock)
                {
                    return Err("isolation_failed");
                }
                if mode == "write"
                    && fs::read(workspace.join("result.txt")).ok().as_deref() != Some(b"CC_WRITTEN")
                {
                    return Err("isolation_failed");
                }
            }
        }
        self.active()?;
        Ok(())
    }
}

fn run(executable: &Path, root: &Path, cancel: Receiver<()>, limit: Duration) -> Value {
    let mut runner = Runner {
        executable,
        root,
        cancel,
        started: Instant::now(),
        wall_started: SystemTime::now(),
        limit,
        children: Vec::new(),
    };
    let status = match runner.check() {
        Ok(()) => "passed",
        Err(status) => status,
    };
    json!({"status":status, "contract":CONTRACT, "version":VERSION,
        "children":runner.children, "elapsed_ms":runner.started.elapsed().as_millis()})
}

pub fn main(args: &[String]) {
    let (sender, cancel) = mpsc::channel();
    thread::spawn(move || {
        let _ = io::stdin().read(&mut [0]);
        let _ = sender.send(());
    });
    let result = match args {
        [path, root] if Path::new(path).is_absolute() => run(
            Path::new(path),
            Path::new(root),
            cancel,
            Duration::from_secs(20),
        ),
        _ => json!({"status":"launch_failed"}),
    };
    let _ = writeln!(io::stdout(), "{result}");
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{os::unix::fs::PermissionsExt, path::PathBuf};

    fn fixture() -> PathBuf {
        let root = PathBuf::from(format!(
            "/private/tmp/cuckoding-isolation-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::DirBuilder::new().mode(0o700).create(&root).unwrap();
        root
    }

    #[test]
    fn refuses_existing_fixtures_and_unsupported_runtimes_without_sandbox_execution() {
        let root = fixture();
        let (_tx, rx) = mpsc::channel();
        let result = run(
            Path::new("/usr/bin/true"),
            &root,
            rx,
            Duration::from_secs(2),
        );
        assert_eq!(result["status"], "unsupported_version");
        assert_eq!(result["children"].as_array().unwrap().len(), 1);
        let (_tx, rx) = mpsc::channel();
        assert_eq!(
            run(
                Path::new("/usr/bin/true"),
                &root,
                rx,
                Duration::from_secs(2)
            )["status"],
            "unsafe_fixture"
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn network_control_waits_for_a_connection_within_the_deadline() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let address = listener.local_addr().unwrap();
        let (_tx, cancel) = mpsc::channel();
        let runner = Runner {
            executable: Path::new("/bin/false"),
            root: Path::new("/"),
            cancel,
            started: Instant::now(),
            wall_started: SystemTime::now(),
            limit: Duration::from_secs(1),
            children: Vec::new(),
        };
        let client = thread::spawn(move || {
            thread::sleep(Duration::from_millis(40));
            TcpStream::connect(address).unwrap()
        });
        runner.accept_control(&listener).unwrap();
        drop(client.join().unwrap());
        let mut expired = runner;
        expired.limit = Duration::ZERO;
        assert_eq!(expired.accept_control(&listener), Err("timeout"));
    }

    #[test]
    fn cancellation_and_timeout_kill_owned_processes_before_receipt() {
        for cancel in [true, false] {
            let root = fixture();
            let path = root.join("provider");
            fs::write(&path, "#!/bin/sh\nsleep 30\n").unwrap();
            fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
            let scratch = root.join("test");
            fs::DirBuilder::new().mode(0o700).create(&scratch).unwrap();
            let (tx, rx) = mpsc::channel();
            let signal = thread::spawn(move || {
                thread::sleep(Duration::from_millis(80));
                if cancel {
                    let _ = tx.send(());
                }
                thread::sleep(Duration::from_millis(300));
            });
            let result = run(&path, &scratch, rx, Duration::from_millis(250));
            assert_eq!(
                result["status"],
                if cancel { "cancelled" } else { "timeout" }
            );
            let pid = result["children"][0]["pid"].as_i64().unwrap() as i32;
            assert_eq!(unsafe { libc::kill(pid, 0) }, -1);
            assert_eq!(unsafe { libc::kill(-pid, 0) }, -1);
            signal.join().unwrap();
            fs::remove_dir_all(root).unwrap();
        }
    }

    #[test]
    fn a_runtime_ignoring_permissions_fails_without_returning_its_output() {
        let root = fixture();
        let path = root.join("provider");
        fs::write(
            &path,
            format!(
                r#"#!/bin/sh
if test "$1" = --version; then printf 'codex-cli {VERSION}\n'; exit 0; fi
while test "$1" != --; do shift; done
shift
exec "$@"
"#
            ),
        )
        .unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
        let scratch = root.join("test");
        fs::DirBuilder::new().mode(0o700).create(&scratch).unwrap();
        let (_tx, rx) = mpsc::channel();
        let result = run(&path, &scratch, rx, Duration::from_secs(3));
        assert_eq!(result["status"], "isolation_failed");
        assert!(!result.to_string().contains("CC_PRIVATE"));
        assert!(scratch.join("first/forbidden.txt").exists());
        fs::remove_dir_all(root).unwrap();
    }

    // Explicit opt-in; routine fixture tests never discover/execute a personal runtime.
    #[test]
    #[ignore = "requires an explicitly selected supported macOS Codex executable"]
    fn real_codex_two_workspace_isolation() {
        let executable = std::env::var("CUCKODING_TEST_CODEX").expect("select the executable");
        let root = fixture();
        let (_tx, rx) = mpsc::channel();
        let receipt = run(Path::new(&executable), &root, rx, Duration::from_secs(20));
        assert_eq!(receipt["status"], "passed", "{receipt}");
        assert_eq!(receipt["children"].as_array().unwrap().len(), 5);
        fs::remove_dir_all(root).unwrap();
    }
}
