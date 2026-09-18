use std::{
    fs::{self, OpenOptions, Permissions},
    io::{BufRead, BufReader, Read, Write},
    net::TcpStream,
    os::unix::{
        fs::{OpenOptionsExt, PermissionsExt},
        process::CommandExt,
    },
    process::{Child, Command, Stdio},
    sync::{Arc, Mutex},
    thread,
    time::{Duration, Instant},
};

use serde_json::Value;
use tauri::{
    image::Image,
    menu::{AboutMetadataBuilder, Menu, MenuItem, PredefinedMenuItem},
    tray::TrayIconBuilder,
    ActivationPolicy, Manager,
};

const VERSION: &str = env!("CARGO_PKG_VERSION");

struct Runtime {
    child: Mutex<Child>,
    pgid: i32,
    port: u16,
    shell_token: String,
    log_path: std::path::PathBuf,
}

struct RemoveOnDrop(std::path::PathBuf);

impl Drop for RemoveOnDrop {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}

fn main() {
    block_shutdown_signals().expect("failed to install shutdown signal mask");

    let app = tauri::Builder::default()
        .setup(|app| {
            app.handle()
                .set_activation_policy(ActivationPolicy::Accessory)?;
            let runtime = Arc::new(start_runtime(app)?);

            if let Err(error) = build_tray(app, runtime.clone()) {
                force_stop(&runtime);
                return Err(error);
            }

            app.manage(runtime);
            start_shutdown_listener(app.handle().clone());
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("Cuckoding shell failed");

    app.run(|handle, event| match event {
        tauri::RunEvent::ExitRequested { api, .. } => {
            if let Some(runtime) = handle.try_state::<Arc<Runtime>>() {
                if stop_runtime(&runtime).is_err() {
                    api.prevent_exit();
                }
            }
        }
        tauri::RunEvent::Exit => {
            if let Some(runtime) = handle.try_state::<Arc<Runtime>>() {
                force_stop_if_running(&runtime);
            }
        }
        _ => {}
    });
}

fn start_runtime(app: &mut tauri::App) -> Result<Runtime, Box<dyn std::error::Error>> {
    let port = free_port()?;
    let data_dir = app.path().app_data_dir()?;
    fs::create_dir_all(&data_dir)?;
    fs::set_permissions(&data_dir, Permissions::from_mode(0o700))?;

    let bootstrap = random_token()?;
    let session_secret = format!("{}{}", random_token()?, random_token()?);
    let file_id = random_token()?;
    let token_path = data_dir.join(format!("bootstrap-{}", &file_id[..16]));
    let _token_cleanup = RemoveOnDrop(token_path.clone());

    OpenOptions::new()
        .create_new(true)
        .write(true)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW)
        .open(&token_path)?
        .write_all(format!("{session_secret}\n{bootstrap}").as_bytes())?;

    let release = app.path().resource_dir()?.join("release/bin/cuckoding");
    let log_path = data_dir.join("control-plane.log");
    let stderr = OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW)
        .open(&log_path)?;
    fs::set_permissions(&log_path, Permissions::from_mode(0o600))?;

    let mut migrate = release_command(&release, &data_dir, port, &token_path);
    let migration_status = migrate
        .args(["eval", "Cuckoding.Release.migrate()"])
        .stdin(Stdio::null())
        .stdout(Stdio::from(stderr.try_clone()?))
        .stderr(Stdio::from(stderr.try_clone()?))
        .status()?;
    if !migration_status.success() {
        return Err("database migration failed".into());
    }

    let mut command = release_command(&release, &data_dir, port, &token_path);
    command
        .arg("start")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::from(stderr));

    unsafe {
        command.pre_exec(|| {
            let mut signals = std::mem::zeroed();
            libc::sigemptyset(&mut signals);
            let mask = libc::pthread_sigmask(libc::SIG_SETMASK, &signals, std::ptr::null_mut());
            if mask != 0 {
                return Err(std::io::Error::from_raw_os_error(mask));
            }

            if libc::setpgid(0, 0) == 0 {
                Ok(())
            } else {
                Err(std::io::Error::last_os_error())
            }
        });
    }

    let mut child = command.spawn()?;
    let pgid = child.id() as i32;
    let stdout = child.stdout.take().ok_or("missing child stdout")?;

    let initialized = (|| {
        wait_ready(stdout, port, Duration::from_secs(15))?;
        let (status, body) = http(port, "POST", "/shell/bootstrap", Some(&bootstrap))?;
        if status != 200 {
            return Err(format!("bootstrap exchange returned HTTP {status}").into());
        }

        Ok::<_, Box<dyn std::error::Error>>(
            serde_json::from_str::<Value>(&body)?["shell_token"]
                .as_str()
                .ok_or("missing shell token")?
                .to_owned(),
        )
    })();

    let shell_token = match initialized {
        Ok(token) => token,
        Err(error) => {
            kill_process_group(&mut child, pgid);
            return Err(error);
        }
    };

    Ok(Runtime {
        child: Mutex::new(child),
        pgid,
        port,
        shell_token,
        log_path,
    })
}

fn release_command(
    release: &std::path::Path,
    data_dir: &std::path::Path,
    port: u16,
    token_path: &std::path::Path,
) -> Command {
    let mut command = Command::new(release);
    command
        .env_clear()
        .env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
        .env("HOME", data_dir)
        .env("LANG", "en_US.UTF-8")
        .env("PHX_SERVER", "true")
        .env("RELEASE_DISTRIBUTION", "none")
        .env("CUCKODING_PORT", port.to_string())
        .env(
            "CUCKODING_DATABASE_PATH",
            data_dir.join("cuckoding.sqlite3"),
        )
        .env("CUCKODING_BOOTSTRAP_FILE", token_path);
    command
}

fn build_tray(
    app: &mut tauri::App,
    runtime: Arc<Runtime>,
) -> Result<(), Box<dyn std::error::Error>> {
    let status = MenuItem::with_id(app, "status", "Ready", false, None::<&str>)?;
    let open = MenuItem::with_id(app, "open", "Cuckoding", true, None::<&str>)?;
    let about_metadata = AboutMetadataBuilder::new()
        .name(Some("Cuckoding"))
        .version(Some(VERSION))
        .credits(Some(format!(
            "Control plane: 127.0.0.1:{}\nRelease notes: https://github.com/mpakus/cuckoding.com/releases",
            runtime.port
        )))
        .build();
    let about = PredefinedMenuItem::about(app, Some("About Cuckoding"), Some(about_metadata))?;
    let settings = MenuItem::with_id(app, "settings", "Settings", true, None::<&str>)?;
    let logs = MenuItem::with_id(app, "logs", "Open Logs", true, None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(
        app,
        &[&status, &open, &about, &settings, &logs, &separator, &quit],
    )?;
    let icon = Image::new_owned([0, 0, 0, 255].repeat(16 * 16), 16, 16);

    let menu_runtime = runtime.clone();
    let quit_status = status.clone();
    TrayIconBuilder::new()
        .icon(icon)
        .icon_as_template(true)
        .tooltip("Cuckoding")
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(move |app, event| match event.id().as_ref() {
            "open" => open_browser(&menu_runtime, "/"),
            "settings" => open_browser(&menu_runtime, "/settings/plugins"),
            "logs" => open_path(&menu_runtime.log_path),
            "quit" => match stop_runtime(&menu_runtime) {
                Ok(()) => app.exit(0),
                Err(_) => {
                    let _ = quit_status.set_text("Quit blocked · open logs");
                }
            },
            _ => {}
        })
        .build(app)?;

    thread::spawn(move || loop {
        thread::sleep(Duration::from_secs(3));
        if runtime
            .child
            .lock()
            .unwrap()
            .try_wait()
            .ok()
            .flatten()
            .is_some()
        {
            let _ = status.set_text("Stopped unexpectedly · open logs");
            break;
        }

        if let Ok((200, body)) = http(
            runtime.port,
            "GET",
            "/shell/status",
            Some(&runtime.shell_token),
        ) {
            if let Ok(value) = serde_json::from_str::<Value>(&body) {
                let runs = value["active_runs"].as_u64().unwrap_or(0);
                let attention = value["attention"].as_u64().unwrap_or(0);
                let _ = status.set_text(format!("{runs} running · {attention} need attention"));
            }
        }
    });

    Ok(())
}

fn open_browser(runtime: &Runtime, path: &str) {
    if let Ok((200, body)) = http(
        runtime.port,
        "POST",
        "/shell/tokens",
        Some(&runtime.shell_token),
    ) {
        if let Ok(value) = serde_json::from_str::<Value>(&body) {
            if let Some(token) = value["token"].as_str() {
                let url = format!(
                    "http://127.0.0.1:{}/open?token={token}&next={path}",
                    runtime.port
                );
                let _ = Command::new("/usr/bin/open").arg(url).spawn();
            }
        }
    }
}

fn open_path(path: &std::path::Path) {
    let _ = Command::new("/usr/bin/open").arg(path).spawn();
}

fn stop_runtime(runtime: &Runtime) -> Result<(), Box<dyn std::error::Error>> {
    if runtime.child.lock().unwrap().try_wait()?.is_some() {
        return Ok(());
    }

    let (status, _) = http(
        runtime.port,
        "POST",
        "/shell/shutdown",
        Some(&runtime.shell_token),
    )?;
    if status != 200 {
        return Err(format!("shutdown policy returned HTTP {status}").into());
    }

    let deadline = Instant::now() + Duration::from_secs(3);
    while Instant::now() < deadline {
        if runtime.child.lock().unwrap().try_wait()?.is_some() {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(50));
    }

    force_stop(runtime);
    Ok(())
}

fn force_stop(runtime: &Runtime) {
    let mut child = runtime.child.lock().unwrap();
    kill_process_group(&mut child, runtime.pgid);
}

fn force_stop_if_running(runtime: &Runtime) {
    let running = runtime
        .child
        .lock()
        .unwrap()
        .try_wait()
        .ok()
        .flatten()
        .is_none();

    if running {
        force_stop(runtime);
    }
}

fn kill_process_group(child: &mut Child, pgid: i32) {
    for signal in [libc::SIGINT, libc::SIGTERM, libc::SIGKILL] {
        unsafe { libc::killpg(pgid, signal) };
        thread::sleep(Duration::from_millis(250));
        if child.try_wait().ok().flatten().is_some() {
            return;
        }
    }
}

fn block_shutdown_signals() -> std::io::Result<()> {
    unsafe {
        let mut signals = std::mem::zeroed();
        libc::sigemptyset(&mut signals);
        libc::sigaddset(&mut signals, libc::SIGINT);
        libc::sigaddset(&mut signals, libc::SIGTERM);
        let result = libc::pthread_sigmask(libc::SIG_BLOCK, &signals, std::ptr::null_mut());
        if result == 0 {
            Ok(())
        } else {
            Err(std::io::Error::from_raw_os_error(result))
        }
    }
}

fn start_shutdown_listener(handle: tauri::AppHandle) {
    thread::spawn(move || unsafe {
        let mut signals = std::mem::zeroed();
        libc::sigemptyset(&mut signals);
        libc::sigaddset(&mut signals, libc::SIGINT);
        libc::sigaddset(&mut signals, libc::SIGTERM);
        let mut received = 0;

        if libc::sigwait(&signals, &mut received) == 0 {
            if let Some(runtime) = handle.try_state::<Arc<Runtime>>() {
                if stop_runtime(&runtime).is_ok() {
                    handle.exit(0);
                }
            }
        }
    });
}

fn wait_ready(
    stdout: impl Read + Send + 'static,
    expected_port: u16,
    timeout: Duration,
) -> Result<(), Box<dyn std::error::Error>> {
    let (sender, receiver) = std::sync::mpsc::channel();
    thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            if let Some(payload) = line.strip_prefix("READY ") {
                let _ = sender.send(payload.to_owned());
                return;
            }
        }
    });

    let payload = receiver.recv_timeout(timeout)?;
    let ready: Value = serde_json::from_str(&payload)?;
    if ready["port"].as_u64() == Some(expected_port as u64)
        && ready["version"].as_str() == Some(VERSION)
    {
        Ok(())
    } else {
        Err("READY payload mismatch".into())
    }
}

fn http(
    port: u16,
    method: &str,
    path: &str,
    bearer: Option<&str>,
) -> Result<(u16, String), Box<dyn std::error::Error>> {
    let mut stream = TcpStream::connect(("127.0.0.1", port))?;
    stream.set_read_timeout(Some(Duration::from_secs(3)))?;
    write!(
        stream,
        "{method} {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nConnection: close\r\nContent-Length: 0\r\n"
    )?;
    if let Some(token) = bearer {
        write!(stream, "Authorization: Bearer {token}\r\n")?;
    }
    write!(stream, "\r\n")?;

    let mut response = String::new();
    stream.read_to_string(&mut response)?;
    let (head, body) = response
        .split_once("\r\n\r\n")
        .ok_or("invalid HTTP response")?;
    let status = head
        .split_whitespace()
        .nth(1)
        .ok_or("missing HTTP status")?
        .parse()?;
    Ok((status, body.to_owned()))
}

fn free_port() -> std::io::Result<u16> {
    let listener = std::net::TcpListener::bind(("127.0.0.1", 0))?;
    Ok(listener.local_addr()?.port())
}

fn random_token() -> Result<String, getrandom::Error> {
    let mut bytes = [0_u8; 32];
    getrandom::fill(&mut bytes)?;
    Ok(bytes.iter().map(|byte| format!("{byte:02x}")).collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn ready_requires_exact_prefix_port_and_version() {
        let input = Cursor::new(
            format!("noise\nREADY {{\"port\":43123,\"version\":\"{VERSION}\"}}\n").into_bytes(),
        );
        assert!(wait_ready(input, 43123, Duration::from_millis(10)).is_ok());
    }

    #[test]
    fn ready_rejects_wrong_version() {
        let input = Cursor::new(b"READY {\"port\":43123,\"version\":\"wrong\"}\n".to_vec());
        assert!(wait_ready(input, 43123, Duration::from_millis(10)).is_err());
    }

    #[test]
    fn ready_rejects_exit_before_signal() {
        assert!(wait_ready(Cursor::new(Vec::new()), 43123, Duration::from_millis(10)).is_err());
    }

    #[test]
    fn token_is_32_random_bytes_in_hex() {
        assert_eq!(random_token().unwrap().len(), 64);
    }
}
