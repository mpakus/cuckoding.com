use serde_json::{json, Value};
use std::{
    fs::{self, File, OpenOptions},
    io::{self, BufRead, BufReader, Read, Write},
    net::{SocketAddr, TcpStream},
    os::unix::{fs::OpenOptionsExt, io::AsRawFd, process::CommandExt},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

pub struct Service {
    child: OwnedChild,
    pub port: u16,
    token: String,
    _lock: DataLock,
}

struct DataLock(File);
impl Drop for DataLock {
    fn drop(&mut self) {
        // A concurrent fork may briefly inherit the descriptor before exec closes it.
        // Explicit unlock ends this shell's ownership without waiting for that copy.
        unsafe { libc::flock(self.0.as_raw_fd(), libc::LOCK_UN) };
    }
}

struct OwnedChild(Child);

impl Drop for OwnedChild {
    fn drop(&mut self) {
        let _ = terminate(&mut self.0);
    }
}

struct BootstrapFile(PathBuf);
impl Drop for BootstrapFile {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}

fn random_hex(bytes: usize) -> io::Result<String> {
    let mut value = vec![0; bytes];
    File::open("/dev/urandom")?.read_exact(&mut value)?;
    Ok(value.iter().map(|b| format!("{b:02x}")).collect())
}

fn data_lock(root: &Path) -> Result<DataLock> {
    if !root.is_absolute() {
        return Err("data directory must be absolute".into());
    }
    let mut current = PathBuf::new();
    for component in root.components() {
        current.push(component);
        if fs::symlink_metadata(&current).is_ok_and(|m| m.file_type().is_symlink()) {
            return Err("data directory contains a symbolic link".into());
        }
    }
    fs::create_dir_all(root)?;
    let marker = root.join(".ccoding-rebuild-v1");
    if fs::symlink_metadata(&marker).is_ok_and(|m| m.file_type().is_symlink()) {
        return Err("unsafe data marker".into());
    }
    if marker.exists() {
        if fs::read_to_string(marker)? != "ccoding-rebuild-v1\n" {
            return Err("unrecognized data directory".into());
        }
    } else if fs::read_dir(root)?.next().is_some() {
        return Err("existing data requires an explicit migration".into());
    }
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(root, fs::Permissions::from_mode(0o700))?;
    let path = root.join("shell.lock");
    if fs::symlink_metadata(&path).is_ok_and(|m| !m.is_file()) {
        return Err("unsafe shell lock".into());
    }
    let file = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .mode(0o600)
        .open(path)?;
    // Held for the lifetime of the shell, so two instances cannot migrate the same DB.
    if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        return Err("Cuckoding is already running for this workspace".into());
    }
    Ok(DataLock(file))
}

impl Service {
    pub fn launch(release: &Path, root: &Path, discovery_home: Option<&str>) -> Result<Self> {
        let lock = data_lock(root)?;
        let bootstrap = random_hex(32)?;
        let boot = BootstrapFile(root.join(format!("launch-{}", random_hex(12)?)));
        let mut file = OpenOptions::new()
            .create_new(true)
            .write(true)
            .mode(0o600)
            .open(&boot.0)?;
        file.write_all(
            serde_json::to_string(&json!({"bootstrap":bootstrap, "signing":random_hex(64)?}))?
                .as_bytes(),
        )?;
        file.sync_all()?;
        drop(file);

        let home = root.join("runtime-home");
        if fs::symlink_metadata(&home).is_ok_and(|m| !m.is_dir()) {
            return Err("unsafe runtime home".into());
        }
        // The application validates the marker before private runtime directories are made.
        if !root.join(".ccoding-rebuild-v1").exists() {
            let mut marker = OpenOptions::new()
                .create_new(true)
                .write(true)
                .mode(0o600)
                .open(root.join(".ccoding-rebuild-v1"))?;
            marker.write_all(b"ccoding-rebuild-v1\n")?;
        }
        fs::create_dir_all(&home)?;
        let mut command = Command::new(release.join("bin/cuckoding"));
        command
            .arg("start")
            .env_clear()
            .env("HOME", &home)
            .env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
            .env("LANG", "en_US.UTF-8")
            .env("TZ", "UTC")
            .env("RELEASE_DISTRIBUTION", "none")
            .env("CCODING_DATA_DIR", root)
            .env("CCODING_BOOTSTRAP_FILE", &boot.0)
            .env("CCODING_NATIVE_HELPER", std::env::current_exe()?)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .current_dir(root)
            .process_group(0);
        if let Some(home) = discovery_home {
            command.env("CCODING_DISCOVERY_HOME", home);
        }
        let mut child = OwnedChild(command.spawn()?);
        let stdout = child.0.stdout.take().ok_or("missing readiness pipe")?;
        let (sender, receiver) = mpsc::sync_channel(1);
        thread::spawn(move || {
            let mut reader = BufReader::new(stdout);
            loop {
                let mut line = Vec::new();
                let read = (&mut reader).take(1025).read_until(b'\n', &mut line);
                if !matches!(read, Ok(n) if n > 0 && n <= 1024) {
                    break;
                }
                if let Some(body) = line.strip_prefix(b"CCODING_READY ") {
                    if let Ok(value) = serde_json::from_slice::<Value>(body) {
                        if let Some(port) = value["port"].as_u64().filter(|p| *p > 0 && *p <= 65535)
                        {
                            let _ = sender.try_send(port as u16);
                        }
                    }
                }
            }
        });
        let port = receiver
            .recv_timeout(Duration::from_secs(30))
            .map_err(|_| "local service did not become ready")?;
        let result = request(port, "/shell/bootstrap", &bootstrap)?;
        let token = result["token"]
            .as_str()
            .filter(|s| s.len() <= 128)
            .ok_or("invalid authorization response")?
            .to_owned();
        Ok(Self {
            child,
            port,
            token,
            _lock: lock,
        })
    }

    pub fn open_url(&self, view: &str) -> Result<String> {
        let response = request(self.port, "/shell/open", &self.token)?;
        let token = response["token"].as_str().ok_or("missing handoff")?;
        if !token
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
        {
            return Err("invalid handoff".into());
        }
        let view = match view {
            "/settings" => "%2Fsettings",
            "/about" => "%2Fabout",
            _ => "%2F",
        };
        Ok(format!(
            "http://127.0.0.1:{}/open?token={token}&view={view}",
            self.port
        ))
    }

    pub fn heartbeat(&mut self) -> Result<()> {
        if self.child.0.try_wait()?.is_some() {
            return Err("local service exited".into());
        }
        request(self.port, "/shell/status", &self.token)?;
        Ok(())
    }

    pub fn smoke_browser(&self) -> Result<()> {
        let fetch = |path: &str, extra: &str| -> Result<String> {
            let mut stream = TcpStream::connect(("127.0.0.1", self.port))?;
            stream.set_read_timeout(Some(Duration::from_secs(3)))?;
            write!(
                stream,
                "GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{}\r\n{extra}Connection: close\r\n\r\n",
                self.port
            )?;
            let mut response = String::new();
            stream.take(65_536).read_to_string(&mut response)?;
            Ok(response)
        };
        if !fetch("/settings", "")?.starts_with("HTTP/1.1 302 ") {
            return Err("unauthorized browser was not redirected".into());
        }
        let url = self.open_url("/settings")?;
        let (_, query) = url.split_once("/open?").ok_or("invalid handoff URL")?;
        let path = format!("/open?{query}");
        let response = fetch(&path, "")?;
        if !response.starts_with("HTTP/1.1 302 ") {
            return Err("handoff was not accepted".into());
        }
        let cookie = response
            .lines()
            .find_map(|line| line.strip_prefix("set-cookie: "))
            .ok_or("no browser cookie")?;
        let flags = cookie.to_ascii_lowercase();
        if !flags.contains("httponly") || !flags.contains("samesite=strict") {
            return Err("browser cookie missing protections".into());
        }
        let cookie = cookie.split(';').next().ok_or("invalid browser cookie")?;
        let headers = format!("Cookie: {cookie}\r\n");
        let page = fetch("/settings", &headers)?;
        if !page.starts_with("HTTP/1.1 200 ") || !page.contains("Build your roster.") {
            return Err("authenticated browser page unavailable".into());
        }
        if !fetch(&path, "")?.starts_with("HTTP/1.1 401 ") {
            return Err("handoff replay accepted".into());
        }
        if !fetch("/settings", &(headers + "Origin: https://evil.test\r\n"))?
            .starts_with("HTTP/1.1 403 ")
        {
            return Err("foreign origin accepted".into());
        }
        Ok(())
    }

    pub fn shutdown(&mut self) -> Result<()> {
        let _ = request(self.port, "/shell/quit", &self.token);
        let deadline = Instant::now() + Duration::from_secs(8);
        while Instant::now() < deadline {
            if self.child.0.try_wait()?.is_some() {
                return Ok(());
            }
            thread::sleep(Duration::from_millis(50));
        }
        terminate(&mut self.child.0)?;
        Ok(())
    }
}

fn terminate(child: &mut Child) -> io::Result<()> {
    if child.try_wait()?.is_some() {
        return Ok(());
    }
    // A live Child handle proves this unreaped group leader is still ours.
    let pgid = child.id() as i32;
    unsafe {
        libc::kill(-pgid, libc::SIGTERM);
    }
    let deadline = Instant::now() + Duration::from_secs(2);
    while Instant::now() < deadline {
        if child.try_wait()?.is_some() {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(20));
    }
    if child.try_wait()?.is_none() {
        unsafe {
            libc::kill(-pgid, libc::SIGKILL);
        }
        child.wait()?;
    }
    Ok(())
}

fn request(port: u16, path: &str, token: &str) -> Result<Value> {
    if !token
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
    {
        return Err("invalid local authorization".into());
    }
    let address = SocketAddr::from(([127, 0, 0, 1], port));
    let mut stream = TcpStream::connect_timeout(&address, Duration::from_secs(2))?;
    stream.set_read_timeout(Some(Duration::from_secs(3)))?;
    stream.set_write_timeout(Some(Duration::from_secs(3)))?;
    write!(stream, "POST {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nAuthorization: Bearer {token}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")?;
    let mut response = String::new();
    stream.take(8193).read_to_string(&mut response)?;
    if response.len() > 8192 {
        return Err("oversized local response".into());
    }
    let (headers, body) = response
        .split_once("\r\n\r\n")
        .ok_or("invalid local response")?;
    if !headers.starts_with("HTTP/1.1 200 ") && !headers.starts_with("HTTP/1.1 202 ") {
        return Err("local service rejected the request".into());
    }
    serde_json::from_str(body).map_err(|_| "invalid local response body".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp() -> PathBuf {
        let path =
            PathBuf::from("/private/tmp").join(format!("ccoding-rust-{}", random_hex(10).unwrap()));
        fs::create_dir(&path).unwrap();
        path
    }

    #[test]
    fn random_material_is_bounded_and_distinct() {
        let a = random_hex(32).unwrap();
        assert_eq!(a.len(), 64);
        assert_ne!(a, random_hex(32).unwrap());
    }

    #[test]
    fn old_data_symlinks_and_second_instance_are_refused() {
        let root = temp();
        fs::write(root.join("old.db"), b"keep").unwrap();
        assert!(data_lock(&root).is_err());
        assert_eq!(fs::read(root.join("old.db")).unwrap(), b"keep");
        fs::remove_file(root.join("old.db")).unwrap();
        let first = data_lock(&root).unwrap();
        fs::write(root.join(".ccoding-rebuild-v1"), b"ccoding-rebuild-v1\n").unwrap();
        assert!(data_lock(&root).is_err());
        let inherited = first.0.try_clone().unwrap();
        drop(first);
        assert!(data_lock(&root).is_ok());
        drop(inherited);
        let link = root.with_extension("link");
        std::os::unix::fs::symlink(&root, &link).unwrap();
        assert!(data_lock(&link).is_err());
        fs::remove_file(link).unwrap();
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn only_the_owned_child_is_stopped() {
        let mut owned = Command::new("/bin/sleep")
            .arg("30")
            .process_group(0)
            .spawn()
            .unwrap();
        let mut other = Command::new("/bin/sleep")
            .arg("30")
            .process_group(0)
            .spawn()
            .unwrap();
        terminate(&mut owned).unwrap();
        assert!(owned.try_wait().unwrap().is_some());
        assert!(other.try_wait().unwrap().is_none());
        terminate(&mut other).unwrap();
    }

    #[test]
    fn authorization_cannot_inject_headers() {
        assert!(request(1, "/shell/status", "bad\r\nHost: evil").is_err());
    }
}
