//! Fixed, bounded version probe. Provider output never becomes a diagnostic.
use serde_json::{json, Value};
use std::{
    fs,
    io::{self, Read, Write},
    os::unix::{fs::PermissionsExt, process::CommandExt},
    path::Path,
    process::{Child, Command, Stdio},
    sync::mpsc::{self, Receiver},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

struct Group(Child);
impl Drop for Group {
    fn drop(&mut self) {
        // Never reap before group cleanup: the unreaped leader pins its PID/PGID.
        unsafe { libc::kill(-(self.0.id() as i32), libc::SIGTERM) };
        thread::sleep(Duration::from_millis(100));
        unsafe { libc::kill(-(self.0.id() as i32), libc::SIGKILL) };
        let _ = self.0.wait();
    }
}

fn exited(child: &Child) -> io::Result<bool> {
    let mut info: libc::siginfo_t = unsafe { std::mem::zeroed() };
    let result = unsafe {
        libc::waitid(
            libc::P_PID,
            child.id(),
            &mut info,
            libc::WEXITED | libc::WNOHANG | libc::WNOWAIT,
        )
    };
    if result != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(unsafe { info.si_pid() } != 0)
}

fn private_directory(path: &Path) -> io::Result<()> {
    if !path.is_absolute() {
        return Err(io::ErrorKind::InvalidInput.into());
    }
    let mut current = std::path::PathBuf::new();
    for component in path.components() {
        current.push(component);
        if fs::symlink_metadata(&current)?.file_type().is_symlink() {
            return Err(io::ErrorKind::PermissionDenied.into());
        }
    }
    let metadata = fs::metadata(path)?;
    if !metadata.is_dir() || metadata.permissions().mode() & 0o077 != 0 {
        return Err(io::ErrorKind::PermissionDenied.into());
    }
    Ok(())
}

fn version(bytes: &[u8]) -> Option<&str> {
    let text = std::str::from_utf8(bytes).ok()?;
    let version = text.strip_prefix("codex-cli ")?.strip_suffix('\n')?;
    let parts: Vec<_> = version.split('.').collect();
    (parts.len() == 3
        && parts
            .iter()
            .all(|p| !p.is_empty() && p.len() <= 5 && p.bytes().all(|b| b.is_ascii_digit())))
    .then_some(version)
}

fn run(path: &Path, directory: &Path, cancel: Receiver<()>, limit: Duration) -> io::Result<Value> {
    private_directory(directory)?;
    let executable = fs::canonicalize(path)?;
    let metadata = fs::metadata(&executable)?;
    if !path.is_absolute() || !metadata.is_file() || metadata.permissions().mode() & 0o111 == 0 {
        return Err(io::ErrorKind::InvalidInput.into());
    }
    let started = Instant::now();
    let spawned_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| io::Error::other("clock unavailable"))?
        .as_millis();
    let mut group = Group(
        Command::new(executable)
            .arg("--version")
            .env_clear()
            .env("HOME", directory)
            .env("CODEX_HOME", directory)
            .env("TMPDIR", directory)
            .env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
            .env("LANG", "en_US.UTF-8")
            .env("TZ", "UTC")
            .current_dir(directory)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .process_group(0)
            .spawn()?,
    );
    let pid = group.0.id();
    let stdout = group.0.stdout.take().ok_or(io::ErrorKind::BrokenPipe)?;
    let (sender, output) = mpsc::sync_channel(1);
    thread::spawn(move || {
        let mut bytes = Vec::new();
        let read = stdout.take(129).read_to_end(&mut bytes);
        let _ = sender.send(read.map(|_| bytes));
    });
    let mut bytes = None;
    let status = loop {
        if cancel.try_recv().is_ok() {
            break "cancelled";
        }
        if started.elapsed() >= limit {
            break "timeout";
        }
        if let Ok(result) = output.try_recv() {
            bytes = Some(result?);
        }
        if bytes.as_ref().is_some_and(|b| b.len() > 128) {
            break "invalid_output";
        }
        if exited(&group.0)? && bytes.is_some() {
            break "observed";
        }
        thread::sleep(Duration::from_millis(10));
    };
    // Check exit status without releasing ownership before all descendants are stopped.
    let mut info: libc::siginfo_t = unsafe { std::mem::zeroed() };
    let successful = unsafe {
        libc::waitid(
            libc::P_PID,
            pid,
            &mut info,
            libc::WEXITED | libc::WNOHANG | libc::WNOWAIT,
        ) == 0
            && info.si_pid() != 0
            && info.si_code == libc::CLD_EXITED
            && info.si_status() == 0
    };
    drop(group);
    let observed = bytes.as_deref().and_then(version).filter(|_| successful);
    let status = if status == "observed" && observed.is_none() {
        "invalid_output"
    } else {
        status
    };
    Ok(
        json!({"status": status, "version": if status == "observed" { observed } else { None },
        "pid": pid, "spawned_at_ms": spawned_at, "elapsed_ms": started.elapsed().as_millis()}),
    )
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
            Duration::from_secs(5),
        ),
        _ => Err(io::ErrorKind::InvalidInput.into()),
    };
    // No raw I/O errors, paths, command arguments, or provider output on either stream.
    let _ = writeln!(
        io::stdout(),
        "{}",
        result.unwrap_or_else(|_| json!({"status":"launch_failed"}))
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    static SERIAL: AtomicUsize = AtomicUsize::new(0);

    fn fixture(body: &str) -> (std::path::PathBuf, std::path::PathBuf) {
        let directory = std::path::PathBuf::from(format!(
            "/private/tmp/ccoding-probe-{}-{}",
            std::process::id(),
            SERIAL.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&directory).unwrap();
        fs::set_permissions(&directory, fs::Permissions::from_mode(0o700)).unwrap();
        let program = directory.join("codex");
        fs::write(&program, format!("#!/bin/sh\n{body}\n")).unwrap();
        fs::set_permissions(&program, fs::Permissions::from_mode(0o700)).unwrap();
        (directory, program)
    }

    #[test]
    fn split_output_is_normalized_and_environment_is_clean() {
        std::env::set_var("CCODING_PROBE_CANARY", "fixture-not-a-secret");
        let (dir, path) = fixture("test -z \"$CCODING_PROBE_CANARY\" || exit 1\ntest \"$HOME\" = \"$PWD\" || exit 2\ntest \"$CODEX_HOME\" = \"$PWD\" || exit 3\ntest \"$1\" = --version || exit 4\nprintf 'codex-cli '\nprintf '0.146.0\\n'");
        let (_sender, receiver) = mpsc::channel();
        let result = run(&path, &dir, receiver, Duration::from_secs(1)).unwrap();
        assert_eq!(result["version"], "0.146.0");
        assert_eq!(result["status"], "observed");
        assert!(result["pid"].as_u64().unwrap() > 0);
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn malformed_oversized_and_nonzero_output_never_leaks() {
        for body in [
            "echo fixture-secret",
            "printf 'codex-cli 0.146.0\\n'; exit 1",
            "head -c 200 /dev/zero",
        ] {
            let (dir, path) = fixture(body);
            let (_sender, receiver) = mpsc::channel();
            let result = run(&path, &dir, receiver, Duration::from_secs(1)).unwrap();
            assert_eq!(result["status"], "invalid_output");
            assert!(result["version"].is_null());
            assert!(!result.to_string().contains("fixture-secret"));
            fs::remove_dir_all(dir).unwrap();
        }
    }

    #[test]
    fn timeout_and_parent_loss_stop_the_group_but_not_a_peer() {
        let mut peer = Command::new("/bin/sleep").arg("30").spawn().unwrap();
        for cancel in [false, true] {
            let (dir, path) = fixture("trap '' TERM\nsleep 30 &\necho $! > child\nwait");
            let (sender, receiver) = mpsc::channel();
            if cancel {
                thread::spawn(move || {
                    thread::sleep(Duration::from_millis(100));
                    sender.send(()).unwrap();
                });
            }
            let result = run(&path, &dir, receiver, Duration::from_millis(250)).unwrap();
            assert_eq!(
                result["status"],
                if cancel { "cancelled" } else { "timeout" }
            );
            let child: i32 = fs::read_to_string(dir.join("child"))
                .unwrap()
                .trim()
                .parse()
                .unwrap();
            thread::sleep(Duration::from_millis(100));
            assert_eq!(unsafe { libc::kill(child, 0) }, -1);
            assert!(peer.try_wait().unwrap().is_none());
            fs::remove_dir_all(dir).unwrap();
        }
        peer.kill().unwrap();
        peer.wait().unwrap();
    }

    #[test]
    fn linked_or_public_scratch_is_refused() {
        let (dir, path) = fixture("echo codex-cli 0.146.0");
        let link = dir.with_extension("link");
        std::os::unix::fs::symlink(&dir, &link).unwrap();
        assert!(private_directory(&link).is_err());
        fs::set_permissions(&dir, fs::Permissions::from_mode(0o755)).unwrap();
        let (_sender, receiver) = mpsc::channel();
        assert!(run(&path, &dir, receiver, Duration::from_secs(1)).is_err());
        fs::remove_file(link).unwrap();
        fs::remove_dir_all(dir).unwrap();
    }
}
