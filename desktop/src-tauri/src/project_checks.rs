//! Frozen literal checks in a disposable owned checkout, under Codex's fixed sandbox grant.
use crate::probe::{exited, private_directory};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    ffi::{CStr, CString},
    fs::{self, File, OpenOptions},
    io::{self, BufRead, BufReader, Read, Write},
    os::{
        fd::{AsRawFd, FromRawFd},
        unix::{
            fs::{DirBuilderExt, MetadataExt, OpenOptionsExt},
            process::CommandExt,
        },
    },
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver},
    },
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

const VERSION: &str = "0.162.0-alpha.17.2";
const CONTRACT: &str = "codex-check-single-process-v1";
type Result<T> = std::result::Result<T, &'static str>;
type Manifest = BTreeMap<String, (u32, String)>;

fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn identity(value: &Value) -> Result<PathBuf> {
    let path = PathBuf::from(value["path"].as_str().ok_or("executable_changed")?);
    let m = fs::metadata(&path).map_err(|_| "executable_changed")?;
    if !path.is_absolute()
        || !m.is_file()
        || m.mode() & 0o111 == 0
        || m.mode() & 0o6000 != 0
        || value["device"].as_u64() != Some(m.dev())
        || value["inode"].as_u64() != Some(m.ino())
        || value["size"].as_u64() != Some(m.len())
        || value["modified"].as_i64() != Some(m.mtime())
        || value["changed"].as_i64() != Some(m.ctime())
    {
        return Err("executable_changed");
    }
    if value.get("sha256").is_some() && value["sha256"] != executable_hash(&path)? {
        return Err("executable_changed");
    }
    Ok(path)
}

fn executable_hash(path: &Path) -> Result<String> {
    let file = File::open(path).map_err(|_| "executable_changed")?;
    let before = file.metadata().map_err(|_| "executable_changed")?;
    if !before.is_file() || before.len() > 134_217_728 {
        return Err("executable_changed");
    }
    let mut digest = Sha256::new();
    let mut input = file.take(134_217_729);
    let count = io::copy(&mut input, &mut digest).map_err(|_| "executable_changed")?;
    if count != before.len() {
        return Err("executable_changed");
    }
    Ok(format!("{:x}", digest.finalize()))
}

fn helper_identity() -> Result<Value> {
    let path = std::env::current_exe().map_err(|_| "executable_changed")?;
    let m = fs::metadata(&path).map_err(|_| "executable_changed")?;
    let value = json!({"path":path,"device":m.dev(),"inode":m.ino(),"size":m.len(),
        "modified":m.mtime(),"changed":m.ctime(),"sha256":executable_hash(&path)?});
    identity(&value)?;
    Ok(value)
}

fn uuid(value: &Value) -> Result<&str> {
    value
        .as_str()
        .filter(|s| {
            s.len() == 36
                && s.bytes().enumerate().all(|(i, b)| {
                    if [8, 13, 18, 23].contains(&i) {
                        b == b'-'
                    } else {
                        b.is_ascii_digit() || (b'a'..=b'f').contains(&b)
                    }
                })
        })
        .ok_or("invalid_request")
}

fn open_at(parent: &File, name: &str, directory: bool) -> Result<File> {
    let name = CString::new(name).map_err(|_| "unsafe_workspace")?;
    let flags = libc::O_RDONLY
        | libc::O_NOFOLLOW
        | libc::O_CLOEXEC
        | libc::O_NONBLOCK
        | if directory { libc::O_DIRECTORY } else { 0 };
    let fd = unsafe { libc::openat(parent.as_raw_fd(), name.as_ptr(), flags) };
    if fd < 0 {
        return Err("unsafe_workspace");
    }
    Ok(unsafe { File::from_raw_fd(fd) })
}

fn read(parent: &File, path: &str) -> Result<(u32, Vec<u8>)> {
    let mut parts: Vec<_> = path.split('/').collect();
    if parts.iter().any(|p| ["", ".", ".."].contains(p)) {
        return Err("unsafe_workspace");
    }
    let name = parts.pop().ok_or("unsafe_workspace")?;
    let mut parent = parent.try_clone().map_err(|_| "unsafe_workspace")?;
    for part in parts {
        parent = open_at(&parent, part, true)?;
    }
    let file = open_at(&parent, name, false)?;
    let before = file.metadata().map_err(|_| "unsafe_workspace")?;
    if !before.is_file() || before.nlink() != 1 || before.len() > 8_388_608 {
        return Err("unsafe_workspace");
    }
    let mut bytes = Vec::new();
    (&file)
        .take(8_388_609)
        .read_to_end(&mut bytes)
        .map_err(|_| "unsafe_workspace")?;
    let after = file.metadata().map_err(|_| "unsafe_workspace")?;
    if bytes.len() as u64 != before.len()
        || before.len() != after.len()
        || before.ctime() != after.ctime()
        || before.ctime_nsec() != after.ctime_nsec()
        || before.mtime() != after.mtime()
        || before.mtime_nsec() != after.mtime_nsec()
    {
        return Err("source_changed");
    }
    Ok((before.mode(), bytes))
}

struct Directory(*mut libc::DIR);
impl Drop for Directory {
    fn drop(&mut self) {
        unsafe {
            libc::closedir(self.0);
        }
    }
}

fn manifest(root: &File) -> Result<Manifest> {
    let mut pending = vec![(
        root.try_clone().map_err(|_| "unsafe_workspace")?,
        String::new(),
        0,
    )];
    let mut manifest = Manifest::new();
    let mut entries = 0;
    let mut bytes = 0;
    while let Some((directory, prefix, depth)) = pending.pop() {
        if depth > 32 {
            return Err("source_limit");
        }
        let fd = unsafe { libc::dup(directory.as_raw_fd()) };
        if fd < 0 {
            return Err("unsafe_workspace");
        }
        let stream = unsafe { libc::fdopendir(fd) };
        if stream.is_null() {
            unsafe {
                libc::close(fd);
            }
            return Err("unsafe_workspace");
        }
        let stream = Directory(stream);
        unsafe {
            libc::rewinddir(stream.0);
        }
        loop {
            unsafe {
                *libc::__error() = 0;
            }
            let entry = unsafe { libc::readdir(stream.0) };
            if entry.is_null() {
                if unsafe { *libc::__error() } != 0 {
                    return Err("unsafe_workspace");
                }
                break;
            }
            let name = unsafe { CStr::from_ptr((*entry).d_name.as_ptr()) }
                .to_str()
                .map_err(|_| "unsafe_workspace")?;
            if [".", ".."].contains(&name) {
                continue;
            }
            entries += 1;
            if entries > 20_000 {
                return Err("source_limit");
            }
            let path = format!("{prefix}{name}");
            // Include the .git pointer in integrity evidence, but never give it to the check.
            if let Ok(child) = open_at(&directory, name, true) {
                pending.push((child, format!("{path}/"), depth + 1));
            } else {
                let (mode, content) = read(root, &path)?;
                bytes += content.len();
                if bytes > 67_108_864 {
                    return Err("source_limit");
                }
                manifest.insert(path, (mode, hash(&content)));
            }
        }
    }
    Ok(manifest)
}

fn unchanged(root: &File, before: &Manifest) -> bool {
    before.iter().all(|(path, expected)| {
        read(root, path).is_ok_and(|(mode, bytes)| (mode, hash(&bytes)) == *expected)
    })
}

fn policy(
    workspace: &Path,
    scratch: &Path,
    rtk: &Path,
    executable: &Path,
    helper: &Path,
) -> Result<String> {
    let path = |p: &Path| p.to_str().map(str::to_owned).ok_or("unsafe_workspace");
    let mut entries = vec![
        (":root".into(), "deny"),
        (":minimal".into(), "read"),
        (":tmpdir".into(), "deny"),
        (":slash_tmp".into(), "deny"),
        (path(workspace)?, "write"),
        (path(scratch)?, "write"),
        (path(rtk)?, "read"),
        (path(executable)?, "read"),
        (path(helper)?, "read"),
    ];
    for name in [
        ".git",
        ".cuckoding",
        ".codex",
        ".cursor",
        ".claude",
        ".agents",
        "AGENTS.md",
        "AGENTS.override.md",
        "CLAUDE.md",
    ] {
        entries.push((path(&workspace.join(name))?, "deny"));
    }
    let rules = entries
        .iter()
        .map(|(p, mode)| format!("{}=\"{mode}\"", json!(p)))
        .collect::<Vec<_>>()
        .join(",");
    Ok(format!(
        "permissions.cuckoding-check={{filesystem={{{rules}}},network={{enabled=false}}}}"
    ))
}

#[derive(Clone, Debug)]
struct ProcessIdentity {
    pid: i32,
    seconds: u64,
    micros: u64,
}

fn process(pid: i32) -> Result<Option<libc::proc_bsdinfo>> {
    let mut info: libc::proc_bsdinfo = unsafe { std::mem::zeroed() };
    let count = unsafe {
        libc::proc_pidinfo(
            pid,
            libc::PROC_PIDTBSDINFO,
            0,
            (&mut info as *mut libc::proc_bsdinfo).cast(),
            std::mem::size_of_val(&info) as i32,
        )
    };
    if count == std::mem::size_of_val(&info) as i32 {
        return Ok(Some(info));
    }
    if unsafe { libc::kill(pid, 0) } == -1
        && io::Error::last_os_error().raw_os_error() == Some(libc::ESRCH)
    {
        Ok(None)
    } else {
        Err("cleanup_uncertain")
    }
}

impl ProcessIdentity {
    fn current(pid: i32) -> Result<Self> {
        let info = process(pid)?.ok_or("cleanup_uncertain")?;
        Ok(Self {
            pid,
            seconds: info.pbi_start_tvsec,
            micros: info.pbi_start_tvusec,
        })
    }

    fn alive(&self) -> Result<bool> {
        Ok(process(self.pid)?.is_some_and(|p| {
            p.pbi_start_tvsec == self.seconds
                && p.pbi_start_tvusec == self.micros
                && p.pbi_status != 5
        }))
    }
}

// Apple SDK libproc.h + mach/task_info.h: token signalling checks the kernel's
// PID version atomically. A start-time lookup followed by ordinary kill is unsafe.
unsafe extern "C" {
    static mach_task_self_: u32;
    fn task_name_for_pid(task: u32, pid: i32, port: *mut u32) -> i32;
    fn mach_port_deallocate(task: u32, port: u32) -> i32;
    fn proc_signal_with_audittoken(token: *mut [u32; 8], signal: i32) -> i32;
}
fn audit_token(identity: &ProcessIdentity) -> Result<Option<[u32; 8]>> {
    if !identity.alive()? {
        return Ok(None);
    }
    let mut port = 0;
    if unsafe { task_name_for_pid(mach_task_self_, identity.pid, &mut port) } != 0 {
        return if !identity.alive()? {
            Ok(None)
        } else {
            Err("cleanup_uncertain")
        };
    }
    let mut token = [0u32; 8];
    let mut count = 8;
    let result = unsafe { libc::task_info(port, 15, token.as_mut_ptr().cast(), &mut count) };
    unsafe {
        mach_port_deallocate(mach_task_self_, port);
    }
    if !identity.alive()? {
        return Ok(None);
    }
    if result != 0 || count != 8 || token[5] != identity.pid as u32 {
        return Err("cleanup_uncertain");
    }
    Ok(Some(token))
}
fn terminate_bound(identity: &ProcessIdentity) -> bool {
    let deadline = Instant::now() + Duration::from_millis(750);
    loop {
        match audit_token(identity) {
            Ok(None) => return true,
            Ok(Some(mut token)) => {
                let result = unsafe { proc_signal_with_audittoken(&mut token, libc::SIGKILL) };
                if result != 0 && result != libc::ESRCH {
                    return false;
                }
            }
            Err(_) => {}
        }
        if Instant::now() >= deadline {
            return identity.alive() == Ok(false);
        }
        thread::sleep(Duration::from_millis(10));
    }
}

// The check becomes a session leader before exec. With no possible child processes,
// it cannot join another session/group to escape its retained PID/start identity.
fn single_process_limit() -> Result<()> {
    if unsafe { libc::geteuid() } == 0 {
        return Err("unsupported_grant");
    }
    let limit = libc::rlimit {
        rlim_cur: 0,
        rlim_max: 0,
    };
    if unsafe { libc::setrlimit(libc::RLIMIT_NPROC, &limit) } != 0 {
        return Err("unsupported_grant");
    }
    let mut actual = libc::rlimit {
        rlim_cur: 1,
        rlim_max: 1,
    };
    if unsafe { libc::getrlimit(libc::RLIMIT_NPROC, &mut actual) } != 0
        || actual.rlim_cur != 0
        || actual.rlim_max != 0
    {
        return Err("unsupported_grant");
    }
    // Check enforcement before any project code. A permissive platform fails closed.
    let child = unsafe { libc::fork() };
    if child == 0 {
        unsafe { libc::_exit(126) }
    }
    if child > 0 {
        unsafe {
            libc::waitpid(child, std::ptr::null_mut(), 0);
        }
        return Err("unsupported_grant");
    }
    if io::Error::last_os_error().raw_os_error() != Some(libc::EAGAIN) {
        return Err("unsupported_grant");
    }
    Ok(())
}

static STOP_CHECK: AtomicBool = AtomicBool::new(false);
extern "C" fn stop_check(_: i32) {
    STOP_CHECK.store(true, Ordering::Relaxed);
}

fn execute_inner(args: &[String]) -> Result<()> {
    let (request, args) = args.split_first().ok_or("invalid_request")?;
    if request.len() > 8192
        || args.len() > 16
        || args
            .iter()
            .any(|a| a.len() > 256 || a.chars().any(char::is_control))
    {
        return Err("invalid_request");
    }
    let request: Value = serde_json::from_str(request).map_err(|_| "invalid_request")?;
    uuid(&request["request_id"])?;
    uuid(&request["check_id"])?;
    let timeout = Duration::from_secs(
        request["timeout_seconds"]
            .as_u64()
            .filter(|t| (1..=300).contains(t))
            .ok_or("invalid_request")?,
    );
    let helper = identity(&request["helper"])?;
    if std::env::current_exe().ok().as_ref() != Some(&helper) {
        return Err("executable_changed");
    }
    let executable = identity(&request["identity"])?;
    let cwd = Path::new(request["cwd"].as_str().ok_or("unsafe_workspace")?);
    if cwd.canonicalize().ok().as_deref() != Some(cwd) {
        return Err("unsafe_workspace");
    }
    let directory = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_DIRECTORY)
        .open(cwd)
        .map_err(|_| "unsafe_workspace")?;
    if unsafe { libc::fchdir(directory.as_raw_fd()) } != 0 {
        return Err("unsafe_workspace");
    }
    unsafe {
        libc::signal(libc::SIGTERM, stop_check as *const () as libc::sighandler_t);
        libc::signal(libc::SIGINT, stop_check as *const () as libc::sighandler_t);
    }
    let protocol_fd = unsafe { libc::fcntl(libc::STDOUT_FILENO, libc::F_DUPFD_CLOEXEC, 3) };
    if protocol_fd < 0 {
        return Err("launch_failed");
    }
    let protocol = unsafe { File::from_raw_fd(protocol_fd) };
    let mut command = Command::new(executable);
    command
        .args(args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    // The sole pre-grant fork is native supervision. Project code starts only
    // after its irreversible process limit and session boundary are enforced.
    let grant = request.clone();
    unsafe {
        command.pre_exec(move || {
            single_process_limit().map_err(|_| io::Error::from(io::ErrorKind::PermissionDenied))?;
            if libc::setsid() != libc::getpid() {
                return Err(io::ErrorKind::PermissionDenied.into());
            }
            let own = ProcessIdentity::current(libc::getpid())
                .map_err(|_| io::ErrorKind::PermissionDenied)?;
            // execute_inner is single-threaded until spawn returns. This trusted
            // pre-exec barrier publishes ownership before any project instruction.
            let frame = json!({"contract": CONTRACT, "request_id": grant["request_id"],
                "check_id": grant["check_id"], "pid": own.pid, "seconds": own.seconds,
                "micros": own.micros, "parent_group": libc::getpgid(libc::getppid())});
            writeln!(&protocol, "{frame}")?;
            let mut byte = 0u8;
            if libc::read(libc::STDIN_FILENO, (&mut byte as *mut u8).cast(), 1) != 1 || byte != b'g'
            {
                return Err(io::ErrorKind::Interrupted.into());
            }
            let null = libc::open(c"/dev/null".as_ptr(), libc::O_RDONLY);
            if null < 0 || libc::dup2(null, libc::STDIN_FILENO) < 0 {
                return Err(io::Error::last_os_error());
            }
            libc::close(null);
            Ok(())
        });
    }
    let child = command.spawn().map_err(|_| "unsupported_grant")?;
    let mut owned = OwnedGroup {
        child,
        finished: false,
    };
    let child = &mut owned.child;
    let child_identity = ProcessIdentity::current(child.id() as i32)?;
    let mut stdout = io::stdout().lock();
    let output = capture(child.stdout.take().ok_or("launch_failed")?, false);
    thread::spawn(|| {
        let _ = io::stdin().read(&mut [0]);
        STOP_CHECK.store(true, Ordering::Relaxed);
    });
    let started = Instant::now();
    let wall = SystemTime::now();
    let mut status = Ok(());
    let mut captured = None;
    loop {
        if let Ok(Output::Finished(value)) = output.try_recv() {
            captured = Some(value);
            if captured
                .as_ref()
                .is_some_and(|v| v.as_ref().is_ok_and(|(count, _)| *count > 65_536))
            {
                status = Err("output_limit");
            }
        }
        if STOP_CHECK.load(Ordering::Relaxed) {
            status = Err("cancelled");
        }
        if started.elapsed() >= timeout || wall.elapsed().unwrap_or(timeout) >= timeout {
            status = Err("timeout");
        }
        if status.is_err() {
            break;
        }
        match exited(child) {
            Ok(true) if captured.is_some() => break,
            Ok(_) => thread::sleep(Duration::from_millis(10)),
            Err(_) => {
                status = Err("cleanup_uncertain");
                break;
            }
        }
    }
    // This is our direct child and has never been reaped. Its PID cannot be
    // reused between signal and wait; no public PID is ever used as authority.
    let _ = child.kill();
    let exit = child.wait();
    owned.finished = exit.is_ok();
    if captured.is_none() {
        if let Ok(Output::Finished(value)) = output.recv_timeout(Duration::from_millis(200)) {
            captured = Some(value);
        }
    }
    let cleaned = exit.is_ok();
    let code = exit.ok().and_then(|s| s.code()).unwrap_or(-1);
    let (bytes, digest) = match captured {
        Some(Ok(value)) => value,
        _ => {
            status = Err("invalid_output");
            (0, hash(b""))
        }
    };
    let status = if !cleaned {
        "cleanup_uncertain"
    } else {
        status
            .err()
            .unwrap_or(if code == 0 { "passed" } else { "failed" })
    };
    let final_frame = json!({"contract":CONTRACT,"request_id":request["request_id"],"check_id":request["check_id"],
        "pid":child_identity.pid,"seconds":child_identity.seconds,"micros":child_identity.micros,
        "cleanup_verified":cleaned,"status":status,"exit_code":code,
        "stdout_bytes":bytes.min(65_536),"stdout_sha256":digest});
    writeln!(stdout, "{final_frame}")
        .and_then(|_| stdout.flush())
        .map_err(|_| "invalid_output")?;
    Ok(())
}

pub fn execute(args: &[String]) {
    let result = execute_inner(args);
    // Never fall through into the UI, or run a check after failed grant enforcement.
    std::process::exit(if result.is_ok() { 0 } else { 126 });
}

struct OwnedGroup {
    child: Child,
    finished: bool,
}
impl OwnedGroup {
    fn signal(&self, signal: i32) -> bool {
        (unsafe { libc::kill(-(self.child.id() as i32), signal) }) == 0
            || io::Error::last_os_error().raw_os_error() == Some(libc::ESRCH)
    }

    fn cleanup(&mut self) -> bool {
        // EOF lets the supervisor finish its receipt while Codex/RTK still keep
        // the output pipe open. Killing the wrappers first would lose evidence.
        drop(self.child.stdin.take());
        let grace = Instant::now() + Duration::from_secs(2);
        while matches!(exited(&self.child), Ok(false)) && Instant::now() < grace {
            thread::sleep(Duration::from_millis(10));
        }
        if !matches!(exited(&self.child), Ok(true)) {
            self.signal(libc::SIGTERM);
            let grace = Instant::now() + Duration::from_secs(1);
            while matches!(exited(&self.child), Ok(false)) && Instant::now() < grace {
                thread::sleep(Duration::from_millis(10));
            }
        }
        self.signal(libc::SIGKILL);
        let deadline = Instant::now() + Duration::from_secs(1);
        loop {
            match self.child.try_wait() {
                Ok(Some(_)) => {
                    self.finished = true;
                    break;
                }
                Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(10)),
                _ => return false,
            }
        }
        // Darwin may return EPERM when signalling an exited group leader.
        // Verify disappearance after reaping instead of inferring it from kill.
        (unsafe { libc::kill(-(self.child.id() as i32), 0) }) == -1
            && io::Error::last_os_error().raw_os_error() == Some(libc::ESRCH)
    }
}
impl Drop for OwnedGroup {
    fn drop(&mut self) {
        if !self.finished {
            self.signal(libc::SIGKILL);
            let _ = self.child.wait();
        }
    }
}

enum Output {
    Header(Value),
    Completed(Value),
    Finished(Result<(usize, String)>),
}

fn capture(stdout: impl Read + Send + 'static, header: bool) -> Receiver<Output> {
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || {
        let mut reader = BufReader::new(stdout);
        if header {
            for first in [true, false] {
                let mut frame = String::new();
                let value = reader
                    .by_ref()
                    .take(2049)
                    .read_line(&mut frame)
                    .ok()
                    .filter(|_| frame.len() <= 2048 && frame.ends_with('\n'))
                    .and_then(|_| serde_json::from_str(&frame).ok())
                    .unwrap_or(Value::Null);
                let _ = tx.send(if first {
                    Output::Header(value)
                } else {
                    Output::Completed(value)
                });
            }
            return;
        }
        let mut bytes = Vec::new();
        let result = reader
            .take(65_537)
            .read_to_end(&mut bytes)
            .map_err(|_| "invalid_output")
            .map(|_| (bytes.len(), hash(&bytes[..bytes.len().min(65_536)])));
        let _ = tx.send(Output::Finished(result));
    });
    rx
}

struct Runner {
    cancel: Receiver<()>,
    started: Instant,
    wall: SystemTime,
    limit: Duration,
    journal: Option<File>,
    receipts: Vec<Value>,
    cleanup_verified: bool,
}
impl Runner {
    fn active(&self) -> Result<()> {
        if self.cancel.try_recv().is_ok() {
            return Err("cancelled");
        }
        if self.started.elapsed() >= self.limit
            || self.wall.elapsed().unwrap_or(self.limit) >= self.limit
        {
            return Err("timeout");
        }
        Ok(())
    }

    fn record(&mut self, value: &Value) -> Result<()> {
        let file = self.journal.as_mut().ok_or("journal_failed")?;
        writeln!(file, "{value}")
            .and_then(|_| file.sync_all())
            .map_err(|_| "journal_failed")
    }

    fn command(
        &mut self,
        command: &mut Command,
        timeout: Duration,
        id: &str,
        token: Option<&str>,
    ) -> Result<Value> {
        self.active()?;
        self.record(&json!({"state":"intent","id":id}))?;
        let started = Instant::now();
        let wall = SystemTime::now();
        let child = command
            .stdin(if token.is_some() {
                Stdio::piped()
            } else {
                Stdio::null()
            })
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .process_group(0)
            .spawn()
            .map_err(|_| "launch_failed")?;
        let mut group = OwnedGroup {
            child,
            finished: false,
        };
        let pid = group.child.id();
        let timestamp = wall
            .duration_since(UNIX_EPOCH)
            .map_err(|_| "launch_failed")?
            .as_millis();
        let mut receipt = json!({"id":id,"pid":pid,"spawned_at_ms":timestamp,"exit_code":-1,
            "stdout_bytes":0,"stdout_sha256":hash(b""),"elapsed_ms":0,"cleanup_verified":false});
        let output = capture(
            group.child.stdout.take().ok_or("launch_failed")?,
            token.is_some(),
        );
        let mut header = None;
        let mut completed = None;
        let mut finished = false;
        let mut status =
            self.record(&json!({"state":"launched","id":id,"pid":pid,"spawned_at_ms":timestamp}));
        while status.is_ok() {
            status = self.active();
            if status.is_ok()
                && (started.elapsed() >= timeout || wall.elapsed().unwrap_or(timeout) >= timeout)
            {
                status = Err("timeout");
            }
            while let Ok(event) = output.try_recv() {
                match event {
                    Output::Header(frame) => header = Some(frame),
                    Output::Completed(frame) => {
                        completed = Some(frame);
                        finished = true;
                    }
                    Output::Finished(value) => {
                        finished = true;
                        match value {
                            Ok((bytes, digest)) => {
                                receipt["stdout_bytes"] = json!(bytes.min(65_536));
                                receipt["stdout_sha256"] = json!(digest);
                                if bytes > 65_536 {
                                    status = Err("output_limit");
                                }
                            }
                            Err(error) => status = Err(error),
                        }
                    }
                }
            }
            if let Some(frame) = header.take() {
                if frame["contract"] == CONTRACT
                    && frame["request_id"] == token.unwrap_or("")
                    && frame["check_id"] == id
                    && frame["parent_group"] == pid
                    && frame["pid"]
                        .as_i64()
                        .is_some_and(|p| p > 1 && p <= i32::MAX as i64)
                    && frame["seconds"].as_u64().is_some()
                    && frame["micros"].as_u64().is_some_and(|v| v < 1_000_000)
                {
                    receipt["child_pid"] = frame["pid"].clone();
                    receipt["child_start_seconds"] = frame["seconds"].clone();
                    receipt["child_start_microseconds"] = frame["micros"].clone();
                    let identity = ProcessIdentity {
                        pid: receipt["child_pid"].as_i64().unwrap() as i32,
                        seconds: receipt["child_start_seconds"].as_u64().unwrap(),
                        micros: receipt["child_start_microseconds"].as_u64().unwrap(),
                    };
                    if let Err(error) =
                        audit_token(&identity).and_then(|token| token.ok_or("cleanup_uncertain"))
                    {
                        status = Err(error);
                    }
                    if let Err(error) = self.record(&json!({"state":"child","receipt":receipt})) {
                        status = Err(error);
                    }
                    if status.is_ok()
                        && group
                            .child
                            .stdin
                            .as_mut()
                            .is_none_or(|input| input.write_all(b"g").is_err())
                    {
                        status = Err("cancelled");
                    }
                } else {
                    status = Err("invalid_output");
                }
            }
            if status.is_err() {
                break;
            }
            match exited(&group.child) {
                Ok(true) if finished => break,
                Ok(_) => thread::sleep(Duration::from_millis(10)),
                Err(_) => {
                    status = Err("cleanup_uncertain");
                    break;
                }
            }
        }
        let mut info: libc::siginfo_t = unsafe { std::mem::zeroed() };
        let observed = unsafe {
            libc::waitid(
                libc::P_PID,
                pid,
                &mut info,
                libc::WEXITED | libc::WNOHANG | libc::WNOWAIT,
            ) == 0
                && info.si_pid() != 0
        };
        if observed && info.si_code == libc::CLD_EXITED {
            receipt["exit_code"] = json!(unsafe { info.si_status() });
        }
        let bound = match (
            receipt["child_pid"].as_i64(),
            receipt["child_start_seconds"].as_u64(),
            receipt["child_start_microseconds"].as_u64(),
        ) {
            (Some(pid), Some(seconds), Some(micros)) => Some(ProcessIdentity {
                pid: pid as i32,
                seconds,
                micros,
            }),
            _ => None,
        };
        // An untrusted check may kill its same-sandbox supervisor. Atomic audit
        // signalling safely cleans that exact session even if the supervisor died.
        let fallback_cleaned = bound.as_ref().is_some_and(terminate_bound);
        let group_cleaned = group.cleanup();
        // A stop may arrive before either frame. The supervisor's private output
        // survives cleanup; retain it, but never infer child cleanup from group exit.
        while let Ok(event) = output.recv_timeout(Duration::from_millis(200)) {
            match event {
                Output::Header(frame) => {
                    if frame["contract"] == CONTRACT
                        && frame["request_id"] == token.unwrap_or("")
                        && frame["check_id"] == id
                        && frame["parent_group"] == pid
                    {
                        receipt["child_pid"] = frame["pid"].clone();
                        receipt["child_start_seconds"] = frame["seconds"].clone();
                        receipt["child_start_microseconds"] = frame["micros"].clone();
                        if let Err(error) = self.record(&json!({"state":"child","receipt":receipt}))
                        {
                            status = Err(error);
                        }
                    }
                }
                Output::Completed(frame) => completed = Some(frame),
                Output::Finished(Ok((bytes, digest))) => {
                    receipt["stdout_bytes"] = json!(bytes.min(65_536));
                    receipt["stdout_sha256"] = json!(digest);
                }
                Output::Finished(Err(_)) => {}
            }
        }
        let child_cleaned = if token.is_some() {
            if let Some(frame) = completed {
                let valid = frame["contract"] == CONTRACT
                    && frame["request_id"] == token.unwrap_or("")
                    && frame["check_id"] == id
                    && frame["pid"] == receipt["child_pid"]
                    && frame["seconds"] == receipt["child_start_seconds"]
                    && frame["micros"] == receipt["child_start_microseconds"]
                    && frame["stdout_bytes"].as_u64().is_some_and(|n| n <= 65_536)
                    && frame["stdout_sha256"]
                        .as_str()
                        .is_some_and(|s| s.len() == 64 && s.bytes().all(|b| b.is_ascii_hexdigit()))
                    && frame["exit_code"]
                        .as_i64()
                        .is_some_and(|n| (-1..=255).contains(&n));
                if valid {
                    for field in ["stdout_bytes", "stdout_sha256", "exit_code"] {
                        receipt[field] = frame[field].clone();
                    }
                    if status.is_ok() {
                        status = match frame["status"].as_str() {
                            Some("passed" | "failed") => Ok(()),
                            Some("timeout") => Err("timeout"),
                            Some("cancelled") => Err("cancelled"),
                            Some("output_limit") => Err("output_limit"),
                            _ => Err("invalid_output"),
                        };
                    }
                }
                valid && frame["cleanup_verified"] == true
            } else {
                false
            }
        } else {
            true
        };
        if token.is_some() && !child_cleaned && status.is_ok() {
            status = Err("invalid_output");
        }
        let cleaned = group_cleaned && (child_cleaned || fallback_cleaned);
        self.cleanup_verified &= cleaned;
        if !cleaned {
            status = Err("cleanup_uncertain");
        }
        receipt["cleanup_verified"] = json!(cleaned);
        receipt["elapsed_ms"] = json!(started.elapsed().as_millis());
        receipt["status"] = json!(match status {
            Err(error) => error,
            Ok(()) if receipt["exit_code"] == 0 => "passed",
            _ => "failed",
        });
        if token.is_some() {
            self.receipts.push(receipt.clone());
        }
        self.record(&json!({"state":"completed","receipt":receipt}))?;
        match status {
            Ok(()) => Ok(receipt),
            Err(error) => Err(error),
        }
    }

    fn child_command(executable: &Path, cwd: &Path, profile: &Path, temp: &Path) -> Command {
        let mut command = Command::new(executable);
        command
            .env_clear()
            .env("HOME", profile)
            .env("CODEX_HOME", profile)
            .env("TMPDIR", temp)
            .env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
            .env("LANG", "en_US.UTF-8")
            .env("TZ", "UTC")
            .env("RTK_NO_TRACKING", "1")
            .current_dir(cwd);
        command
    }

    fn run(&mut self, request: &Value, home: &Path) -> Result<()> {
        self.active()?;
        private_directory(home).map_err(|_| "unsafe_workspace")?;
        if home.file_name().and_then(|s| s.to_str()) != Some("runtime-home") {
            return Err("unsafe_workspace");
        }
        let key = uuid(&request["request_id"])?;
        let data = home.parent().ok_or("unsafe_workspace")?;
        let scratch = data.join("probes").join(format!("{key}-1"));
        if request["scratch"].as_str() != scratch.to_str() {
            return Err("unsafe_workspace");
        }
        private_directory(&scratch).map_err(|_| "unsafe_workspace")?;
        self.active()?;
        let journal = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW)
            .open(scratch.join("check-receipts.jsonl"))
            .map_err(|_| "attempt_exists")?;
        self.journal = Some(journal);
        self.record(&json!({"state":"prepared","request_id":key,"request_sha256":hash(request.to_string().as_bytes()),"candidate_sha":request["workspace"]["head"]}))?;
        File::open(&scratch)
            .and_then(|f| f.sync_all())
            .map_err(|_| "journal_failed")?;
        let profile = scratch.join("profile");
        let temp = scratch.join("tmp");
        for path in [&profile, &temp] {
            self.active()?;
            fs::DirBuilder::new()
                .mode(0o700)
                .create(path)
                .map_err(|_| "attempt_exists")?;
        }
        let workspace = &request["workspace"];
        let workspace_key = uuid(&workspace["key"])?;
        let parent = home.join("worktrees").join(workspace_key);
        let path = parent.join("checkout");
        if workspace["path"].as_str() != path.to_str()
            || path.canonicalize().ok().as_ref() != Some(&path)
        {
            return Err("unsafe_workspace");
        }
        private_directory(&parent).map_err(|_| "unsafe_workspace")?;
        let parent = File::open(parent).map_err(|_| "unsafe_workspace")?;
        let (_, owner) = read(&parent, "owner.json")?;
        let owner: Value = serde_json::from_slice(&owner).map_err(|_| "unsafe_workspace")?;
        if owner
            != json!({"version":1,"key":workspace_key,"head":workspace["head"],"source_device":workspace["source_device"],"source_inode":workspace["source_inode"],"path":path})
        {
            return Err("unsafe_workspace");
        }
        let root = open_at(&parent, "checkout", true)?;
        let m = root.metadata().map_err(|_| "unsafe_workspace")?;
        if workspace["device"].as_u64() != Some(m.dev())
            || workspace["inode"].as_u64() != Some(m.ino())
        {
            return Err("unsafe_workspace");
        }
        self.active()?;
        let before = manifest(&root)?;
        self.active()?;
        let codex = identity(&request["codex"])?;
        let helper = helper_identity()?;
        self.record(&json!({"state":"helper","identity":helper}))?;
        let version = self.command(
            Self::child_command(&codex, &scratch, &profile, &temp).arg("--version"),
            Duration::from_secs(5),
            "version",
            None,
        )?;
        if version["exit_code"] != 0
            || version["stdout_sha256"] != hash(format!("codex-cli {VERSION}\n").as_bytes())
        {
            return Err("unsupported_version");
        }
        let checks = request["checks"]
            .as_array()
            .filter(|v| !v.is_empty() && v.len() <= 8)
            .ok_or("invalid_request")?;
        if checks
            .iter()
            .try_fold(0u64, |sum, c| {
                sum.checked_add(c["timeout_seconds"].as_u64().unwrap_or(601))
            })
            .is_none_or(|v| v > 600)
        {
            return Err("invalid_request");
        }
        for check in checks {
            self.active()?;
            let id = uuid(&check["id"])?;
            let executable = identity(&check["identity"])?;
            let rtk = identity(&check["rtk_identity"])?;
            let helper_path = identity(&helper)?;
            let timeout = check["timeout_seconds"]
                .as_u64()
                .filter(|v| (1..=300).contains(v))
                .ok_or("invalid_request")?;
            let directory = check["directory"].as_str().ok_or("invalid_request")?;
            if directory != "." && directory.split('/').any(|p| ["", ".", ".."].contains(&p)) {
                return Err("unsafe_workspace");
            }
            let cwd = if directory == "." {
                path.clone()
            } else {
                path.join(directory)
            };
            if cwd.canonicalize().ok().as_ref() != Some(&cwd) || !cwd.starts_with(&path) {
                return Err("unsafe_workspace");
            }
            let policy = policy(&path, &temp, &rtk, &executable, &helper_path)?;
            let inner = json!({"request_id":key,"check_id":id,"timeout_seconds":timeout,"cwd":cwd,"identity":check["identity"],"helper":helper});
            let mut command = Self::child_command(&codex, &scratch, &profile, &temp);
            command.args([
                "sandbox",
                "-P",
                "cuckoding-check",
                "-C",
                scratch.to_str().ok_or("unsafe_workspace")?,
                "-c",
                &policy,
                "--",
                rtk.to_str().ok_or("invalid_request")?,
                "proxy",
                helper_path.to_str().ok_or("invalid_request")?,
                "--execute-battle-check",
                &inner.to_string(),
            ]);
            let args = check["arguments"]
                .as_array()
                .filter(|a| a.len() <= 16)
                .ok_or("invalid_request")?;
            for arg in args {
                command.arg(
                    arg.as_str()
                        .filter(|s| s.len() <= 256 && !s.chars().any(char::is_control))
                        .ok_or("invalid_request")?,
                );
            }
            let receipt =
                self.command(&mut command, Duration::from_secs(timeout), id, Some(key))?;
            if !unchanged(&root, &before) {
                return Err("source_changed");
            }
            let after = fs::symlink_metadata(&path).map_err(|_| "unsafe_workspace")?;
            if !after.is_dir() || after.dev() != m.dev() || after.ino() != m.ino() {
                return Err("unsafe_workspace");
            }
            if receipt["status"] != "passed" {
                return Err("failed");
            }
        }
        self.active()
    }
}

pub fn main() {
    let mut stdin = io::stdin().lock();
    let mut line = String::new();
    let request = (&mut stdin)
        .take(65_537)
        .read_line(&mut line)
        .ok()
        .filter(|_| line.len() <= 65_536 && line.ends_with('\n'))
        .and_then(|_| serde_json::from_str::<Value>(&line).ok());
    drop(stdin);
    let (tx, cancel) = mpsc::channel();
    thread::spawn(move || {
        let _ = io::stdin().read(&mut [0]);
        let _ = tx.send(());
    });
    let mut runner = Runner {
        cancel,
        started: Instant::now(),
        wall: SystemTime::now(),
        limit: Duration::from_secs(615),
        journal: None,
        receipts: Vec::new(),
        cleanup_verified: true,
    };
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_default();
    let request = request.unwrap_or(Value::Null);
    let status = runner.run(&request, &home).err().unwrap_or("passed");
    let mut value = json!({"status":status,"contract":CONTRACT,"request_id":request["request_id"],"candidate_sha":request["workspace"]["head"],"checks":runner.receipts,"cleanup_verified":runner.cleanup_verified});
    if runner.journal.is_some()
        && runner
            .record(&json!({"state":"finished","receipt":value}))
            .is_err()
    {
        value["status"] = json!("journal_failed");
    }
    let _ = writeln!(io::stdout(), "{value}");
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::{symlink, PermissionsExt};

    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    struct Fixture(PathBuf);
    impl Fixture {
        fn new() -> Self {
            let path = std::env::temp_dir().canonicalize().unwrap().join(format!(
                "cc-check-{}-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed),
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_nanos()
            ));
            fs::DirBuilder::new().mode(0o700).create(&path).unwrap();
            Self(path)
        }
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
    fn key() -> String {
        let hex = format!(
            "{:032x}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        );
        format!(
            "{}-{}-{}-{}-{}",
            &hex[..8],
            &hex[8..12],
            &hex[12..16],
            &hex[16..20],
            &hex[20..]
        )
    }
    fn file_identity(path: &Path) -> Value {
        let path = path.canonicalize().unwrap();
        let m = fs::metadata(&path).unwrap();
        json!({"path":path,"device":m.dev(),"inode":m.ino(),"size":m.len(),"modified":m.mtime(),"changed":m.ctime()})
    }
    fn runner(journal: Option<File>, cancel: Receiver<()>) -> Runner {
        Runner {
            cancel,
            journal,
            started: Instant::now(),
            wall: SystemTime::now(),
            limit: Duration::from_secs(30),
            receipts: Vec::new(),
            cleanup_verified: true,
        }
    }

    #[test]
    fn pinned_manifest_rejects_replacements_but_allows_new_build_files() {
        let fixture = Fixture::new();
        fs::write(fixture.0.join("source"), "original").unwrap();
        let root = File::open(&fixture.0).unwrap();
        let before = manifest(&root).unwrap();
        fs::write(fixture.0.join("build"), "new").unwrap();
        assert!(unchanged(&root, &before));
        fs::write(fixture.0.join("source"), "changed").unwrap();
        assert!(!unchanged(&root, &before));
        fs::remove_file(fixture.0.join("source")).unwrap();
        symlink("build", fixture.0.join("source")).unwrap();
        assert!(!unchanged(&root, &before));
        assert_eq!(manifest(&root).unwrap_err(), "unsafe_workspace");
    }

    #[test]
    fn cancelled_request_has_no_setup_effects_and_foreign_scratch_is_refused() {
        let fixture = Fixture::new();
        let home = fixture.0.join("runtime-home");
        fs::DirBuilder::new().mode(0o700).create(&home).unwrap();
        let (tx, rx) = mpsc::channel();
        tx.send(()).unwrap();
        assert_eq!(runner(None, rx).run(&Value::Null, &home), Err("cancelled"));
        assert_eq!(fs::read_dir(&fixture.0).unwrap().count(), 1);
        let (_tx, rx) = mpsc::channel();
        assert_eq!(
            runner(None, rx).run(&json!({"request_id":key(),"scratch":fixture.0}), &home),
            Err("unsafe_workspace")
        );
        assert_eq!(fs::read_dir(&fixture.0).unwrap().count(), 1);
    }

    #[test]
    fn timeout_cleans_owned_group_and_preserves_unrelated_peer() {
        let fixture = Fixture::new();
        let journal = File::create(fixture.0.join("journal")).unwrap();
        let (_tx, rx) = mpsc::channel();
        let mut runner = runner(Some(journal), rx);
        let mut peer = Command::new("/bin/sleep").arg("30").spawn().unwrap();
        let outcome = runner.command(
            Command::new("/bin/sleep").arg("30"),
            Duration::from_millis(100),
            "fixture",
            None,
        );
        assert_eq!(outcome, Err("timeout"));
        assert!(runner.cleanup_verified);
        assert!(peer.try_wait().unwrap().is_none());
        peer.kill().unwrap();
        peer.wait().unwrap();
        let journal = fs::read_to_string(fixture.0.join("journal")).unwrap();
        assert!(journal.contains("\"state\":\"launched\""));
        assert!(journal.contains("\"status\":\"timeout\""));
        assert!(journal.contains("\"cleanup_verified\":true"));
    }

    #[test]
    fn historical_pid_identity_does_not_identify_a_current_process() {
        let mut identity = ProcessIdentity::current(unsafe { libc::getpid() }).unwrap();
        identity.seconds += 1;
        assert_eq!(identity.alive(), Ok(false));
        assert!(terminate_bound(&identity));
    }

    #[test]
    fn bounded_capture_hashes_only_the_retained_prefix() {
        let bytes = vec![b'x'; 65_537];
        let output = capture(io::Cursor::new(bytes.clone()), false);
        match output.recv_timeout(Duration::from_secs(1)).unwrap() {
            Output::Finished(Ok((count, digest))) => {
                assert_eq!(count, 65_537);
                assert_eq!(digest, hash(&bytes[..65_536]));
            }
            _ => panic!("missing bounded output"),
        }
    }

    #[test]
    fn executable_identity_rejects_setid_and_changed_bytes() {
        let fixture = Fixture::new();
        let executable = fixture.0.join("tool");
        fs::write(&executable, "first").unwrap();
        fs::set_permissions(&executable, fs::Permissions::from_mode(0o755)).unwrap();
        let mut frozen = file_identity(&executable);
        frozen["sha256"] = json!(hash(b"first"));
        assert!(identity(&frozen).is_ok());
        fs::write(&executable, "other").unwrap();
        assert_eq!(identity(&frozen), Err("executable_changed"));
        fs::set_permissions(&executable, fs::Permissions::from_mode(0o4755)).unwrap();
        assert_eq!(
            identity(&file_identity(&executable)),
            Err("executable_changed")
        );
    }

    // Explicit offline opt-in: no discovery, profile reuse, account or inference.
    // This verifies the actual OS grant, not a mocked sandbox or successful spawn.
    #[test]
    #[ignore = "requires explicitly selected Codex, RTK and freshly built native helper"]
    fn offline_single_process_sandbox_canaries() {
        let codex = PathBuf::from(std::env::var("CUCKODING_TEST_CODEX").unwrap());
        let rtk = PathBuf::from(std::env::var("CUCKODING_TEST_RTK").unwrap());
        let helper = PathBuf::from(std::env::var("CUCKODING_TEST_CHECK_HELPER").unwrap());
        let fixture = Fixture::new();
        let source = fixture.0.join("canary.c");
        let executable = fixture.0.join("canary");
        fs::write(
            &source,
            r#"
#include <sys/resource.h>
#include <sys/wait.h>
#include <spawn.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
extern char **environ;
int main(int argc, char **argv) {
  if (argc != 2) return 10;
  if (!strcmp(argv[1], "limits")) {
    struct rlimit r;
    if (getrlimit(RLIMIT_NPROC,&r) || r.rlim_cur || r.rlim_max) return 11;
    pid_t p=fork(); if (p==0) _exit(12);
    if (p>0) { waitpid(p,0,0); return 13; }
    if (errno != EAGAIN) return 14;
    char *args[]={"true",0};
    if (posix_spawn(&p,"/usr/bin/true",0,0,args,environ) != EAGAIN) return 15;
    if (setsid()!=-1 || errno!=EPERM) return 16;
    if (getpid()!=getsid(0) || getpid()!=getpgrp()) return 17;
    r.rlim_cur=r.rlim_max=100;
    if (setrlimit(RLIMIT_NPROC,&r)!=-1) return 18;
    puts("limited"); return 0;
  }
  if (!strncmp(argv[1], "peer:",5)) {
    int r=kill(atoi(argv[1]+5),SIGUSR1); return r==-1 && errno==EPERM?0:21;
  }
  if (!strcmp(argv[1], "kill-exec")) {
    if (kill(getppid(),SIGKILL)!=0) return 22;
    execl("/bin/sleep","sleep","30",NULL); return 23;
  }
  if (!strcmp(argv[1], "sleep")) {
    signal(SIGTERM,SIG_IGN); puts("started"); fflush(stdout);
    FILE *marker=fopen("started.marker","w"); if (!marker) return 24; fclose(marker);
    sleep(30); return 0;
  }
  if (!strcmp(argv[1], "output")) {
    for (int i=0;i<65537;i++) putchar('x'); fflush(stdout); sleep(30); return 0;
  }
  if (!strcmp(argv[1], "mutate")) {
    FILE *f=fopen("source.txt","w"); if (!f) return 19;
    fputs("changed",f); return fclose(f);
  }
  return 20;
}
"#,
        )
        .unwrap();
        assert!(Command::new("/usr/bin/clang")
            .arg(&source)
            .arg("-o")
            .arg(&executable)
            .status()
            .unwrap()
            .success());
        let mut peer = OwnedGroup {
            child: Command::new("/bin/sleep")
                .arg("120")
                .process_group(0)
                .spawn()
                .unwrap(),
            finished: false,
        };
        let scenarios = [
            "true",
            "failure",
            "protected",
            "foreign",
            "limits",
            "timeout",
            "cancel",
            "output",
            "mutate",
            "peer",
            "kill-exec",
        ];
        for scenario in scenarios {
            let request_id = key();
            let workspace_key = key();
            let data = fixture.0.join(scenario);
            fs::create_dir(&data).unwrap();
            let home = data.join("runtime-home");
            fs::DirBuilder::new().mode(0o700).create(&home).unwrap();
            let scratch = data.join("probes").join(format!("{request_id}-1"));
            fs::DirBuilder::new()
                .recursive(true)
                .mode(0o700)
                .create(&scratch)
                .unwrap();
            let parent = home.join("worktrees").join(&workspace_key);
            let checkout = parent.join("checkout");
            fs::DirBuilder::new()
                .recursive(true)
                .mode(0o700)
                .create(&checkout)
                .unwrap();
            fs::write(checkout.join("source.txt"), "original").unwrap();
            fs::write(checkout.join("AGENTS.md"), "protected canary").unwrap();
            let foreign = data.join("private-canary");
            fs::write(&foreign, "foreign canary").unwrap();
            let m = fs::metadata(&checkout).unwrap();
            let workspace = json!({"key":workspace_key,"head":"a".repeat(40),"source_device":1,"source_inode":2,"path":checkout,"device":m.dev(),"inode":m.ino()});
            fs::write(parent.join("owner.json"),json!({"version":1,"key":workspace["key"],"head":workspace["head"],"source_device":1,"source_inode":2,"path":checkout}).to_string()).unwrap();
            let check = |path: &Path, args: Vec<String>, timeout: u64| json!({"id":key(),"identity":file_identity(path),"rtk_identity":file_identity(&rtk),"arguments":args,"directory":".","timeout_seconds":timeout});
            let selected = match scenario {
                "true" => check(Path::new("/usr/bin/true"), vec![], 10),
                "failure" => check(Path::new("/usr/bin/false"), vec![], 10),
                "protected" => check(Path::new("/bin/cat"), vec!["AGENTS.md".into()], 10),
                "foreign" => check(
                    Path::new("/bin/cat"),
                    vec![foreign.to_str().unwrap().into()],
                    10,
                ),
                "peer" => check(&executable, vec![format!("peer:{}", peer.child.id())], 10),
                "timeout" => check(&executable, vec!["sleep".into()], 3),
                "cancel" => check(&executable, vec!["sleep".into()], 15),
                other => check(&executable, vec![other.into()], 10),
            };
            let request = json!({"request_id":request_id,"scratch":scratch,"workspace":workspace,"codex":file_identity(&codex),
                "checks":[check(Path::new("/usr/bin/true"),vec![],10),selected]});
            let mut child = Command::new(&helper)
                .arg("--battle-checks")
                .env_clear()
                .env("HOME", &home)
                .env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()
                .unwrap();
            let mut input = child.stdin.take().unwrap();
            writeln!(input, "{request}").unwrap();
            input.flush().unwrap();
            if scenario == "cancel" {
                let deadline = Instant::now() + Duration::from_secs(15);
                loop {
                    let text = fs::read_to_string(scratch.join("check-receipts.jsonl"))
                        .unwrap_or_default();
                    if text
                        .lines()
                        .filter(|line| line.contains("\"state\":\"child\""))
                        .count()
                        == 2
                        && checkout.join("started.marker").exists()
                    {
                        break;
                    }
                    assert!(Instant::now() < deadline, "missing second child frame");
                    thread::sleep(Duration::from_millis(20));
                }
                input.write_all(b"x").unwrap();
                input.flush().unwrap();
            }
            let (tx, rx) = mpsc::channel();
            let stdout = child.stdout.take().unwrap();
            thread::spawn(move || {
                let mut line = String::new();
                let _ = BufReader::new(stdout).read_line(&mut line);
                let _ = tx.send(line);
            });
            let line = rx
                .recv_timeout(Duration::from_secs(30))
                .expect("bounded native completion");
            assert!(child.wait().unwrap().success());
            drop(input);
            let result: Value = serde_json::from_str(&line).unwrap();
            let expected = match scenario {
                "true" | "limits" | "peer" => "passed",
                "kill-exec" => "invalid_output",
                "timeout" => "timeout",
                "cancel" => "cancelled",
                "output" => "output_limit",
                "mutate" => "source_changed",
                _ => "failed",
            };
            assert_eq!(result["status"], expected, "{scenario}: {result}");
            assert_eq!(result["cleanup_verified"], true, "{scenario}: {result}");
            let checks = result["checks"].as_array().unwrap();
            assert_eq!(checks.len(), 2, "{result}");
            assert_eq!(checks[0]["status"], "passed");
            assert!(checks.iter().all(|c| c["cleanup_verified"] == true));
            for check in checks {
                assert!(process(check["pid"].as_i64().unwrap() as i32)
                    .unwrap()
                    .is_none());
                let identity = ProcessIdentity {
                    pid: check["child_pid"].as_i64().unwrap() as i32,
                    seconds: check["child_start_seconds"].as_u64().unwrap(),
                    micros: check["child_start_microseconds"].as_u64().unwrap(),
                };
                assert_eq!(identity.alive(), Ok(false));
            }
            if scenario == "cancel" || scenario == "timeout" {
                assert_eq!(checks[1]["stdout_sha256"], hash(b"started\n"));
            }
            assert!(peer.child.try_wait().unwrap().is_none());
            assert_eq!(fs::read_to_string(&foreign).unwrap(), "foreign canary");
            let journal = fs::read_to_string(scratch.join("check-receipts.jsonl")).unwrap();
            assert_eq!(
                journal
                    .lines()
                    .filter(|l| l.contains("\"state\":\"completed\""))
                    .count(),
                3
            );
            assert!(journal.contains("\"state\":\"finished\""));
        }
        assert!(peer.cleanup());
    }
}
