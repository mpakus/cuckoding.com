//! Fixed local Git operations. Repository text never supplies argv or authority.
mod initial;
use crate::probe::{exited, private_directory, Group};
use serde_json::{json, Value};
use std::{
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    os::{
        fd::AsRawFd,
        unix::{
            fs::{MetadataExt, OpenOptionsExt},
            process::CommandExt,
        },
    },
    path::Path,
    process::{Command, Stdio},
    sync::mpsc::{self, Receiver},
    thread,
    time::{Duration, Instant},
};

type Result<T> = std::result::Result<T, &'static str>;

struct Git<'a> {
    root: &'a Path,
    home: &'a Path,
    directory: File,
    cancel: Receiver<()>,
    deadline: Instant,
}

impl Drop for Git<'_> {
    fn drop(&mut self) {
        // Explicit unlock also releases the lock from descriptors inherited during a fork.
        unsafe {
            libc::flock(self.directory.as_raw_fd(), libc::LOCK_UN);
        }
    }
}

impl Git<'_> {
    fn active(&self) -> Result<()> {
        if self.cancel.try_recv().is_ok() {
            return Err("cancelled");
        }
        if Instant::now() >= self.deadline {
            return Err("timeout");
        }
        Ok(())
    }

    fn identity(&self, device: u64, inode: u64) -> Result<()> {
        self.active()?;
        if self.root.canonicalize().ok().as_deref() != Some(self.root) {
            return Err("folder_changed");
        }
        let metadata = fs::symlink_metadata(self.root).map_err(|_| "folder_changed")?;
        let pinned = self.directory.metadata().map_err(|_| "folder_changed")?;
        if !metadata.is_dir()
            || metadata.dev() != device
            || metadata.ino() != inode
            || pinned.dev() != device
            || pinned.ino() != inode
        {
            return Err("folder_changed");
        }
        Ok(())
    }

    fn command(&self, args: &[&str], in_repository: bool) -> Result<(i32, Vec<u8>)> {
        self.command_input(args, in_repository, None, None)
    }

    fn command_input(
        &self,
        args: &[&str],
        in_repository: bool,
        input: Option<Vec<u8>>,
        index: Option<&Path>,
    ) -> Result<(i32, Vec<u8>)> {
        self.active()?;
        let mut command = Command::new("/usr/bin/git");
        command
            .env_clear()
            .env("HOME", self.home)
            .env("XDG_CONFIG_HOME", self.home)
            .env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
            .env("LANG", "C")
            .env("TZ", "UTC")
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .env("GIT_CONFIG_GLOBAL", "/dev/null")
            .env("GIT_CONFIG_SYSTEM", "/dev/null")
            .env("GIT_OPTIONAL_LOCKS", "0")
            .env("GIT_TERMINAL_PROMPT", "0")
            .env("GIT_NO_LAZY_FETCH", "1")
            .env("GIT_ALLOW_PROTOCOL", "")
            .env("GIT_NO_REPLACE_OBJECTS", "1")
            .env("GIT_CEILING_DIRECTORIES", self.home)
            .env("GIT_AUTHOR_NAME", "Cuckoding")
            .env("GIT_AUTHOR_EMAIL", "local@cuckoding.invalid")
            .env("GIT_COMMITTER_NAME", "Cuckoding")
            .env("GIT_COMMITTER_EMAIL", "local@cuckoding.invalid")
            .arg("--no-pager")
            .args([
                "-c",
                "core.hooksPath=/dev/null",
                "-c",
                "core.fsmonitor=false",
                "-c",
                "credential.helper=",
                "-c",
                "core.commitGraph=false",
                "-c",
                "commit.gpgsign=false",
                "-c",
                "core.splitIndex=false",
            ])
            .current_dir(self.home)
            .stdin(if input.is_some() {
                Stdio::piped()
            } else {
                Stdio::null()
            })
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .process_group(0);
        if in_repository {
            let fd = self.directory.as_raw_fd();
            // Pin the selected directory through rename/replacement races.
            unsafe {
                command.pre_exec(move || {
                    if libc::fchdir(fd) == 0 {
                        Ok(())
                    } else {
                        Err(std::io::Error::last_os_error())
                    }
                });
            }
            command.arg("--git-dir=.git");
        }
        command.args(args);
        if let Some(index) = index {
            command.env("GIT_INDEX_FILE", index);
        }
        let mut group = Group(command.spawn().map_err(|_| "git_unavailable")?);
        let writer = if let Some(bytes) = input {
            let mut stdin = group.0.stdin.take().ok_or("git_unavailable")?;
            Some(thread::spawn(move || stdin.write_all(&bytes)))
        } else {
            None
        };
        let stdout = group.0.stdout.take().ok_or("git_unavailable")?;
        let (sender, receiver) = mpsc::sync_channel(1);
        thread::spawn(move || {
            let mut bytes = Vec::new();
            let result = stdout.take(8193).read_to_end(&mut bytes);
            let _ = sender.send(result.map(|_| bytes));
        });
        let mut bytes = None;
        loop {
            self.active()?;
            if let Ok(result) = receiver.try_recv() {
                bytes = Some(result.map_err(|_| "invalid_repository")?);
            }
            if bytes.as_ref().is_some_and(|b| b.len() > 8192) {
                return Err("metadata_limit");
            }
            if exited(&group.0).map_err(|_| "git_unavailable")? && bytes.is_some() {
                break;
            }
            thread::sleep(Duration::from_millis(10));
        }
        let mut info: libc::siginfo_t = unsafe { std::mem::zeroed() };
        let code = unsafe {
            if libc::waitid(
                libc::P_PID,
                group.0.id(),
                &mut info,
                libc::WEXITED | libc::WNOWAIT,
            ) == 0
                && info.si_code == libc::CLD_EXITED
            {
                info.si_status()
            } else {
                -1
            }
        };
        drop(group); // Kill descendants before reaping the owned leader.
        if let Some(writer) = writer {
            writer
                .join()
                .map_err(|_| "recheck_required")?
                .map_err(|_| "recheck_required")?;
        }
        Ok((code, bytes.unwrap_or_default()))
    }

    fn inspect(&self) -> Result<Value> {
        self.active()?;
        // Never discover/adopt a parent repository or create a nested one.
        if self
            .root
            .ancestors()
            .skip(1)
            .any(|p| fs::symlink_metadata(p.join(".git")).is_ok())
        {
            return Err("nested_repository");
        }
        let git = self.root.join(".git");
        match fs::symlink_metadata(&git) {
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                if self.root.join("HEAD").exists() && self.root.join("objects").exists() {
                    return Err("unsupported_layout");
                }
                let (code, _) = self.command(&["--version"], false)?;
                return if code == 0 {
                    Ok(json!({"status":"missing"}))
                } else {
                    Err("git_unavailable")
                };
            }
            Ok(metadata) if metadata.is_dir() && !metadata.file_type().is_symlink() => {}
            _ => return Err("unsupported_layout"),
        }
        self.check_metadata(&git)?;
        let config = git.join("config");
        if fs::metadata(&config)
            .map_err(|_| "invalid_repository")?
            .len()
            > 65_536
        {
            return Err("metadata_limit");
        }
        let (code, keys) = self.command(
            &[
                "config",
                "--no-includes",
                "--file",
                config.to_str().ok_or("unsupported_layout")?,
                "--null",
                "--name-only",
                "--list",
            ],
            false,
        )?;
        let keys = std::str::from_utf8(&keys).map_err(|_| "unsafe_config")?;
        if code != 0
            || keys.split('\0').any(|key| {
                let key = key.to_ascii_lowercase();
                key.starts_with("include.")
                    || key.starts_with("includeif.")
                    || key.starts_with("extensions.")
                    || key == "core.worktree"
                    || key.ends_with(".promisor")
                    || key.ends_with(".partialclonefilter")
            })
        {
            return Err("unsafe_config");
        }
        let (code, bare) = self.command(&["rev-parse", "--is-bare-repository"], true)?;
        if code != 0 || bare != b"false\n" {
            return Err("invalid_repository");
        }
        let (head_code, head) =
            self.command(&["rev-parse", "--verify", "--quiet", "HEAD^{commit}"], true)?;
        if head_code == 0 {
            let hash = std::str::from_utf8(&head)
                .map_err(|_| "invalid_repository")?
                .trim();
            if hash.len() != 40 || !hash.bytes().all(|c| c.is_ascii_hexdigit()) {
                return Err("invalid_repository");
            }
            return Ok(json!({"status":"existing", "head":hash}));
        }
        let (code, branch) = self.command(&["symbolic-ref", "--quiet", "HEAD"], true)?;
        let branch = std::str::from_utf8(&branch)
            .map_err(|_| "invalid_repository")?
            .trim();
        if code != 0
            || !branch.starts_with("refs/heads/")
            || branch.len() > 256
            || branch.chars().any(char::is_control)
        {
            return Err("invalid_repository");
        }
        let (code, _) = self.command(&["show-ref", "--verify", "--quiet", branch], true)?;
        if code == 1 {
            Ok(json!({"status":"unborn"}))
        } else {
            Err("invalid_repository")
        }
    }

    fn check_metadata(&self, git: &Path) -> Result<()> {
        for name in [
            "commondir",
            "config.worktree",
            "objects/info/alternates",
            "objects/info/http-alternates",
        ] {
            if fs::symlink_metadata(git.join(name)).is_ok() {
                return Err("unsupported_layout");
            }
        }
        // ponytail: bounded metadata walk; add scoped linked-layout support only when needed.
        let mut pending = vec![git.to_path_buf()];
        let mut count = 0;
        while let Some(path) = pending.pop() {
            self.active()?;
            for entry in fs::read_dir(path).map_err(|_| "invalid_repository")? {
                self.active()?;
                count += 1;
                if count > 50_000 {
                    return Err("metadata_limit");
                }
                let path = entry.map_err(|_| "invalid_repository")?.path();
                let metadata = fs::symlink_metadata(&path).map_err(|_| "invalid_repository")?;
                if metadata.is_dir() {
                    pending.push(path);
                } else if !metadata.is_file() || metadata.nlink() != 1 {
                    return Err("unsupported_layout");
                }
            }
        }
        Ok(())
    }
}

fn run(args: &[String], cancel: Receiver<()>, limit: Duration) -> Result<Value> {
    let [operation, path, device, inode, home, extra @ ..] = args else {
        return Err("invalid_request");
    };
    if !["inspect", "init", "preview", "commit"].contains(&operation.as_str())
        || extra.len() != usize::from(["preview", "commit"].contains(&operation.as_str()))
        || path.len() > 4096
        || path.chars().any(char::is_control)
    {
        return Err("invalid_request");
    }
    let root = Path::new(path);
    let home = Path::new(home);
    private_directory(home).map_err(|_| "invalid_request")?;
    let directory = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW)
        .open(root)
        .map_err(|_| "folder_changed")?;
    if unsafe { libc::flock(directory.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        return Err("repository_busy");
    }
    let git = Git {
        root,
        home,
        directory,
        cancel,
        deadline: Instant::now() + limit,
    };
    let device = device.parse().map_err(|_| "invalid_request")?;
    let inode = inode.parse().map_err(|_| "invalid_request")?;
    git.identity(device, inode)?;
    if ["preview", "commit"].contains(&operation.as_str()) {
        return initial::run(&git, operation, &extra[0], device, inode);
    }
    let observed = git.inspect()?;
    if operation == "inspect" {
        return Ok(observed);
    }
    if observed["status"] != "missing" {
        return Err("repository_changed");
    }
    git.identity(device, inode)?;
    // Exclusive creation refuses a newly appeared .git; never reinitialize a repository.
    if unsafe { libc::mkdirat(git.directory.as_raw_fd(), c".git".as_ptr(), 0o700) } != 0 {
        return Err("repository_changed");
    }
    let (code, _) = git.command(
        &["init", "--quiet", "--initial-branch=main", "--template="],
        true,
    )?;
    if code != 0 {
        return Err("recheck_required");
    }
    git.identity(device, inode)?;
    let observed = git.inspect()?;
    if observed["status"] == "unborn" {
        Ok(json!({"status":"initialized"}))
    } else {
        Err("recheck_required")
    }
}

pub fn main(args: &[String]) {
    let started = Instant::now();
    let (sender, cancel) = mpsc::channel();
    thread::spawn(move || {
        let _ = std::io::stdin().read(&mut [0]);
        let _ = sender.send(());
    });
    let mut result = run(args, cancel, Duration::from_secs(15))
        .unwrap_or_else(|status| json!({"status":status}));
    result["elapsed_ms"] = json!(started.elapsed().as_millis());
    let _ = writeln!(std::io::stdout(), "{result}");
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        os::unix::fs::PermissionsExt,
        path::PathBuf,
        sync::atomic::{AtomicUsize, Ordering},
    };
    static SERIAL: AtomicUsize = AtomicUsize::new(0);

    fn fixture() -> (PathBuf, PathBuf, Vec<String>) {
        let base = PathBuf::from(format!(
            "/private/tmp/cuckoding-git-{}-{}",
            std::process::id(),
            SERIAL.fetch_add(1, Ordering::Relaxed)
        ));
        let root = base.join("project");
        let home = base.join("private");
        fs::create_dir_all(&root).unwrap();
        fs::create_dir(&home).unwrap();
        fs::set_permissions(&home, fs::Permissions::from_mode(0o700)).unwrap();
        let metadata = fs::metadata(&root).unwrap();
        let args = vec![
            "inspect".into(),
            root.to_str().unwrap().into(),
            metadata.dev().to_string(),
            metadata.ino().to_string(),
            home.to_str().unwrap().into(),
        ];
        (root, home, args)
    }

    fn operation(args: &[String], name: &str) -> Result<Value> {
        let mut args = args.to_vec();
        args[0] = name.into();
        let (_sender, receiver) = mpsc::channel();
        run(&args, receiver, Duration::from_secs(10))
    }

    fn git(root: &Path, home: &Path, args: &[&str]) -> (i32, Vec<u8>) {
        let (_sender, cancel) = mpsc::channel();
        Git {
            root,
            home,
            directory: File::open(root).unwrap(),
            cancel,
            deadline: Instant::now() + Duration::from_secs(10),
        }
        .command(args, true)
        .unwrap()
    }

    #[test]
    fn real_git_missing_init_unborn_commit_and_dirty_files_are_preserved() {
        let (root, home, args) = fixture();
        fs::write(root.join("plan.md"), "fixture plan\n").unwrap();
        assert_eq!(operation(&args, "inspect").unwrap()["status"], "missing");
        assert!(!root.join(".git").exists());
        assert_eq!(operation(&args, "init").unwrap()["status"], "initialized");
        assert_eq!(operation(&args, "inspect").unwrap()["status"], "unborn");
        assert_eq!(
            fs::read_to_string(root.join(".git/HEAD")).unwrap(),
            "ref: refs/heads/main\n"
        );
        assert!(!root.join(".git/hooks").exists());
        assert!(!root.join(".git/index").exists());
        assert_eq!(operation(&args, "init"), Err("repository_changed"));
        assert_eq!(git(&root, &home, &["add", "--", "plan.md"]).0, 0);
        assert_eq!(
            git(
                &root,
                &home,
                &[
                    "-c",
                    "user.name=Fixture",
                    "-c",
                    "user.email=fixture@example.invalid",
                    "commit",
                    "-m",
                    "Fixture baseline"
                ]
            )
            .0,
            0
        );
        fs::write(root.join("plan.md"), "unstaged fixture change\n").unwrap();
        fs::write(root.join("untracked.txt"), "untracked fixture\n").unwrap();
        let index = fs::read(root.join(".git/index")).unwrap();
        let config = fs::read(root.join(".git/config")).unwrap();
        let result = operation(&args, "inspect").unwrap();
        assert_eq!(result["status"], "existing");
        assert_eq!(result["head"].as_str().unwrap().len(), 40);
        assert_eq!(fs::read(root.join(".git/index")).unwrap(), index);
        assert_eq!(fs::read(root.join(".git/config")).unwrap(), config);
        assert_eq!(
            fs::read_to_string(root.join("plan.md")).unwrap(),
            "unstaged fixture change\n"
        );
        assert_eq!(
            fs::read_to_string(root.join("untracked.txt")).unwrap(),
            "untracked fixture\n"
        );
        fs::remove_dir_all(root.parent().unwrap()).unwrap();
    }

    #[test]
    fn external_metadata_config_and_missing_objects_fail_closed() {
        for scenario in [
            "gitfile",
            "gitlink",
            "include",
            "worktree",
            "alternates",
            "objectlink",
            "missing_commit",
            "fifo",
        ] {
            let (root, home, args) = fixture();
            if scenario == "gitfile" {
                fs::write(root.join(".git"), "gitdir: /outside\n").unwrap();
            } else if scenario == "gitlink" {
                std::os::unix::fs::symlink(&home, root.join(".git")).unwrap();
            } else {
                operation(&args, "init").unwrap();
                match scenario {
                    "include" => {
                        fs::write(
                            root.join(".git/config"),
                            "[include]\npath = /outside/fixture-secret\n",
                        )
                        .unwrap();
                    }
                    "worktree" => {
                        fs::write(root.join(".git/config"), "[core]\nworktree = /outside\n")
                            .unwrap();
                    }
                    "alternates" => {
                        fs::create_dir_all(root.join(".git/objects/info")).unwrap();
                        fs::write(root.join(".git/objects/info/alternates"), "/outside\n").unwrap();
                    }
                    "objectlink" => {
                        std::os::unix::fs::symlink(&home, root.join(".git/objects/aa")).unwrap();
                    }
                    "missing_commit" => {
                        fs::write(
                            root.join(".git/refs/heads/main"),
                            format!("{}\n", "1".repeat(40)),
                        )
                        .unwrap();
                    }
                    "fifo" => {
                        let name = std::ffi::CString::new(root.join(".git/trap").to_str().unwrap())
                            .unwrap();
                        assert_eq!(unsafe { libc::mkfifo(name.as_ptr(), 0o600) }, 0);
                    }
                    _ => unreachable!(),
                }
            }
            assert!(operation(&args, "inspect").is_err(), "{scenario}");
            assert!(operation(&args, "init").is_err(), "{scenario}");
            fs::remove_dir_all(root.parent().unwrap()).unwrap();
        }
    }

    #[test]
    fn identity_nesting_cancellation_deadline_and_locking_refuse_effects() {
        let (root, home, args) = fixture();
        let mut changed = args.clone();
        changed[3] = "0".into();
        assert_eq!(operation(&changed, "init"), Err("folder_changed"));
        let (sender, receiver) = mpsc::channel();
        sender.send(()).unwrap();
        assert_eq!(
            run(&args, receiver, Duration::from_secs(1)),
            Err("cancelled")
        );
        let (_sender, receiver) = mpsc::channel();
        assert_eq!(run(&args, receiver, Duration::ZERO), Err("timeout"));
        let (_sender, cancel) = mpsc::channel();
        let mismatched_handle = Git {
            root: &root,
            home: &home,
            directory: File::open(&home).unwrap(),
            cancel,
            deadline: Instant::now() + Duration::from_secs(1),
        };
        assert_eq!(
            mismatched_handle.identity(args[2].parse().unwrap(), args[3].parse().unwrap()),
            Err("folder_changed")
        );
        let lock = File::open(&root).unwrap();
        assert_eq!(
            unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) },
            0
        );
        assert_eq!(operation(&args, "init"), Err("repository_busy"));
        // Other parallel tests may fork while this test holds the descriptor.
        assert_eq!(unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_UN) }, 0);
        drop(lock);
        assert!(!root.join(".git").exists());
        operation(&args, "init").unwrap();
        let nested = root.join("nested");
        fs::create_dir(&nested).unwrap();
        let mut args = args;
        args[1] = nested.to_str().unwrap().into();
        args[3] = fs::metadata(&nested).unwrap().ino().to_string();
        assert_eq!(operation(&args, "init"), Err("nested_repository"));
        assert!(!nested.join(".git").exists());
        assert_eq!(
            git(&root, &home, &["rev-parse", "--is-bare-repository"]).1,
            b"false\n"
        );
        fs::remove_dir_all(root.parent().unwrap()).unwrap();
    }

    #[test]
    fn user_configuration_and_environment_do_not_reach_git() {
        let (root, home, args) = fixture();
        fs::write(
            home.join(".gitconfig"),
            "[include]\npath = /outside\n[init]\ndefaultBranch = wrong\ntemplateDir = /outside\n",
        )
        .unwrap();
        std::env::set_var("GIT_CONFIG_COUNT", "1");
        std::env::set_var("GIT_CONFIG_KEY_0", "init.defaultBranch");
        std::env::set_var("GIT_CONFIG_VALUE_0", "wrong");
        std::env::set_var("GIT_DIR", "/outside");
        assert_eq!(operation(&args, "init").unwrap()["status"], "initialized");
        assert_eq!(
            fs::read_to_string(root.join(".git/HEAD")).unwrap(),
            "ref: refs/heads/main\n"
        );
        for key in [
            "GIT_DIR",
            "GIT_CONFIG_COUNT",
            "GIT_CONFIG_KEY_0",
            "GIT_CONFIG_VALUE_0",
        ] {
            std::env::remove_var(key);
        }
        fs::remove_dir_all(root.parent().unwrap()).unwrap();
    }

    #[test]
    fn cancellation_and_deadline_clean_git_descendants_without_signalling_a_peer() {
        let mut peer = Command::new("/bin/sleep").arg("30").spawn().unwrap();
        for cancelled in [false, true] {
            let (root, home, _) = fixture();
            let (sender, cancel) = mpsc::channel();
            if cancelled {
                thread::spawn(move || {
                    thread::sleep(Duration::from_millis(300));
                    sender.send(()).unwrap();
                });
            }
            let git = Git {
                root: &root,
                home: &home,
                directory: File::open(&root).unwrap(),
                cancel,
                deadline: Instant::now() + Duration::from_millis(700),
            };
            // Only the unit test supplies an alias; production callers use fixed built-ins.
            let alias = "alias.slow=!sleep 30 & echo $! > child; wait";
            assert_eq!(
                git.command(&["-c", alias, "slow"], false),
                Err(if cancelled { "cancelled" } else { "timeout" })
            );
            let child: i32 = fs::read_to_string(home.join("child"))
                .unwrap()
                .trim()
                .parse()
                .unwrap();
            thread::sleep(Duration::from_millis(100));
            assert_eq!(unsafe { libc::kill(child, 0) }, -1);
            assert!(peer.try_wait().unwrap().is_none());
            fs::remove_dir_all(root.parent().unwrap()).unwrap();
        }
        peer.kill().unwrap();
        peer.wait().unwrap();
    }

    fn initial(args: &[String], operation: &str, request: Value) -> Result<Value> {
        let mut args = args.to_vec();
        args[0] = operation.into();
        args.push(request.to_string());
        let (_sender, cancel) = mpsc::channel();
        run(&args, cancel, Duration::from_secs(15))
    }

    fn consent(preview: &Value) -> Value {
        json!({"key":"00000000-0000-4000-8000-000000000001", "preview_id":"00000000-0000-4000-8000-000000000002", "preview":preview["preview"]})
    }

    #[test]
    fn first_commit_contains_only_exact_preview_and_leaves_working_files() {
        let (root, home, args) = fixture();
        operation(&args, "init").unwrap();
        fs::write(root.join(".git/HEAD"), "ref: refs/heads/setup/docs\n").unwrap();
        fs::create_dir(root.join("docs")).unwrap();
        fs::write(root.join("docs/a, b.md"), "previewed bytes\r\n").unwrap();
        fs::write(root.join("run.sh"), "echo fixture\n").unwrap();
        fs::set_permissions(root.join("run.sh"), fs::Permissions::from_mode(0o700)).unwrap();
        fs::write(root.join(".env"), "UNSELECTED_SECRET_CANARY").unwrap();
        let observed =
            initial(&args, "preview", json!({"paths":["docs/a, b.md","run.sh"]})).unwrap();
        assert_eq!(observed["status"], "previewed");
        assert_eq!(observed["preview"]["files"][1]["mode"], "100755");
        assert!(!observed.to_string().contains("UNSELECTED_SECRET_CANARY"));
        assert!(!root.join(".git/index").exists());
        let result = initial(&args, "commit", consent(&observed)).unwrap();
        assert_eq!(result["status"], "committed");
        assert!(root.join(".git/refs/heads/setup/docs").is_file());
        assert!(!root.join(".git/refs/heads/setup/docs.lock").exists());
        assert!(!root.join(".git/packed-refs.lock").exists());
        assert_eq!(
            git(&root, &home, &["rev-list", "--count", "HEAD"]).1,
            b"1\n"
        );
        assert_eq!(
            git(&root, &home, &["ls-tree", "--name-only", "-r", "HEAD"]).1,
            b"docs/a, b.md\nrun.sh\n"
        );
        assert_eq!(
            git(&root, &home, &["cat-file", "blob", "HEAD:docs/a, b.md"]).1,
            b"previewed bytes\r\n"
        );
        assert_eq!(git(&root, &home, &["diff", "--cached", "--quiet"]).0, 0);
        assert_eq!(
            fs::read(root.join("docs/a, b.md")).unwrap(),
            b"previewed bytes\r\n"
        );
        assert_eq!(
            fs::read(root.join(".env")).unwrap(),
            b"UNSELECTED_SECRET_CANARY"
        );
        assert!(!root.join(".git/index.lock").exists());
        assert!(!root.join(".git/HEAD.lock").exists());
        assert_eq!(fs::metadata(root.join(".git/index")).unwrap().nlink(), 1);
        let commit = git(&root, &home, &["cat-file", "-p", "HEAD"]).1;
        let commit = String::from_utf8(commit).unwrap();
        assert!(commit.contains("author Cuckoding <local@cuckoding.invalid>"));
        assert!(commit.contains("Initialize Arena with Cuckoding"));
        assert!(!commit.contains("parent "));
        assert_eq!(
            initial(&args, "commit", consent(&observed)),
            Err("initial_only")
        );
        fs::remove_file(root.join(".git/index")).unwrap();
        fs::write(root.join(".git/HEAD"), "ref: refs/heads/other\n").unwrap();
        assert_eq!(
            initial(&args, "preview", json!({"paths":[]})),
            Err("initial_only")
        );
        fs::remove_dir_all(root.parent().unwrap()).unwrap();
    }

    #[test]
    fn empty_baseline_and_failed_ref_publication_preserve_state() {
        for fail in [false, true] {
            let (root, home, args) = fixture();
            operation(&args, "init").unwrap();
            let observed = initial(&args, "preview", json!({"paths":[]})).unwrap();
            if fail {
                fs::write(root.join(".git/refs/heads/main.lock"), "foreign lock").unwrap();
            }
            let result = initial(&args, "commit", consent(&observed));
            if fail {
                assert_eq!(result, Err("repository_busy"));
                assert_eq!(
                    fs::read(root.join(".git/refs/heads/main.lock")).unwrap(),
                    b"foreign lock"
                );
                assert_eq!(operation(&args, "inspect").unwrap()["status"], "unborn");
                assert!(root.join(".git/index").exists());
                assert_eq!(
                    initial(&args, "preview", json!({"paths":[]})),
                    Err("index_present")
                );
            } else {
                assert_eq!(result.unwrap()["status"], "committed");
                assert_eq!(git(&root, &home, &["ls-tree", "-r", "HEAD"]).1, b"");
            }
            assert!(!root.join(".git/index.lock").exists());
            assert!(!root.join(".git/HEAD.lock").exists());
            fs::remove_dir_all(root.parent().unwrap()).unwrap();
        }
    }

    #[test]
    fn stale_files_config_branch_or_index_refuse_initial_commit() {
        for change in ["file", "mode", "config", "branch", "index", "identity"] {
            let (root, _, args) = fixture();
            operation(&args, "init").unwrap();
            fs::write(root.join("plan.md"), "before").unwrap();
            let observed = initial(&args, "preview", json!({"paths":["plan.md"]})).unwrap();
            match change {
                "file" => fs::write(root.join("plan.md"), "after").unwrap(),
                "mode" => {
                    fs::set_permissions(root.join("plan.md"), fs::Permissions::from_mode(0o700))
                        .unwrap()
                }
                "config" => {
                    let mut f = OpenOptions::new()
                        .append(true)
                        .open(root.join(".git/config"))
                        .unwrap();
                    writeln!(f, "[user]\nname = Changed").unwrap();
                }
                "branch" => fs::write(root.join(".git/HEAD"), "ref: refs/heads/other\n").unwrap(),
                "index" => fs::write(root.join(".git/index"), "existing index bytes").unwrap(),
                "identity" => {
                    fs::rename(root.join(".git"), root.join("saved-git")).unwrap();
                    operation(&args, "init").unwrap();
                }
                _ => unreachable!(),
            }
            assert!(
                initial(&args, "commit", consent(&observed)).is_err(),
                "{change}"
            );
            assert!(!root.join(".git/refs/heads/main").exists());
            assert!(!root.join(".git/index.lock").exists());
            if change == "index" {
                assert_eq!(
                    fs::read(root.join(".git/index")).unwrap(),
                    b"existing index bytes"
                );
            } else {
                assert!(!root.join(".git/index").exists());
            }
            fs::remove_dir_all(root.parent().unwrap()).unwrap();
        }
    }

    #[test]
    fn selection_rejects_escapes_links_special_files_and_bounds() {
        let (root, home, args) = fixture();
        operation(&args, "init").unwrap();
        fs::write(home.join("outside"), "OUTSIDE_CANARY").unwrap();
        std::os::unix::fs::symlink(&home, root.join("linked")).unwrap();
        fs::hard_link(home.join("outside"), root.join("hardlink")).unwrap();
        let pipe = std::ffi::CString::new(root.join("pipe").to_str().unwrap()).unwrap();
        assert_eq!(unsafe { libc::mkfifo(pipe.as_ptr(), 0o600) }, 0);
        fs::write(root.join("large"), vec![0u8; 1_048_577]).unwrap();
        for path in [
            "../outside",
            "/outside",
            ".git/config",
            ".env",
            "docs//x",
            "./x",
            "x\ny",
            "linked/outside",
            "hardlink",
            "pipe",
            "large",
        ] {
            assert!(
                initial(&args, "preview", json!({"paths":[path]})).is_err(),
                "{path}"
            );
        }
        assert!(initial(&args, "preview", json!({"paths":["same","same"]})).is_err());
        assert!(initial(&args, "preview", json!({"paths":vec!["x";17]})).is_err());
        let quoted: Vec<_> = (0..16)
            .map(|i| format!("{i}{}", "\"".repeat(235)))
            .collect();
        for name in &quoted {
            fs::write(root.join(name), "bounded").unwrap();
        }
        assert_eq!(
            initial(&args, "preview", json!({"paths":quoted})),
            Err("selection_limit")
        );
        assert!(!root.join(".git/index").exists());
        fs::remove_dir_all(root.parent().unwrap()).unwrap();
    }
}
