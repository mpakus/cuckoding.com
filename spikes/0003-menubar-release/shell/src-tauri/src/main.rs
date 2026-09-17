use std::{
    fs::{self, OpenOptions},
    io::{BufRead, BufReader, Read, Write},
    net::TcpStream,
    os::unix::{fs::OpenOptionsExt, process::CommandExt},
    process::{Child, Command, Stdio},
    sync::{Arc, Mutex},
    thread,
    time::{Duration, Instant},
};

use serde_json::Value;
use tauri::{
    image::Image,
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::TrayIconBuilder,
    ActivationPolicy, Manager,
};

struct Runtime {
    child: Arc<Mutex<Child>>,
    pgid: i32,
    port: u16,
    shell_token: String,
}

fn main() {
    block_shutdown_signals().expect("failed to install shutdown signal mask");
    let app = tauri::Builder::default()
        .setup(|app| {
            app.handle()
                .set_activation_policy(ActivationPolicy::Accessory)?;
            let runtime = Arc::new(start_runtime(app)?);
            if let Err(error) = build_tray(app, runtime.clone()) {
                stop_runtime(&runtime);
                return Err(error);
            }
            app.manage(runtime);
            start_shutdown_listener(app.handle().clone());
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("shell spike failed");

    app.run(|handle, event| {
        if matches!(event, tauri::RunEvent::Exit) {
            if let Some(runtime) = handle.try_state::<Arc<Runtime>>() {
                stop_runtime(&runtime);
            }
        }
    });
}

fn start_runtime(app: &mut tauri::App) -> Result<Runtime, Box<dyn std::error::Error>> {
    let port = free_port()?;
    let data_dir = app.path().app_data_dir()?;
    fs::create_dir_all(&data_dir)?;
    let token = random_token()?;
    let session_secret = format!("{}{}", random_token()?, random_token()?);
    let token_path = data_dir.join(format!("bootstrap-token-{}", &token[..16]));
    OpenOptions::new()
        .create_new(true)
        .write(true)
        .mode(0o600)
        .open(&token_path)?
        .write_all(format!("{session_secret}\n{token}").as_bytes())?;

    let release = app
        .path()
        .resource_dir()?
        .join("release/bin/cuckoding_shell_spike");
    let stderr = OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .open(data_dir.join("control-plane.log"))?;

    let mut command = Command::new(release);
    command
        .arg("start")
        .env_clear()
        .env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
        .env("HOME", &data_dir)
        .env("LANG", "en_US.UTF-8")
        .env("RELEASE_DISTRIBUTION", "none")
        .env("CUCKODING_PORT", port.to_string())
        .env("CUCKODING_BOOTSTRAP_FILE", &token_path)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::from(stderr));

    unsafe {
        command.pre_exec(|| {
            let mut signals = std::mem::zeroed();
            libc::sigemptyset(&mut signals);
            let result = libc::pthread_sigmask(libc::SIG_SETMASK, &signals, std::ptr::null_mut());
            if result != 0 {
                return Err(std::io::Error::from_raw_os_error(result));
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
        let (status, body) = http(port, "POST", "/shell/bootstrap", Some(&token))?;
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
        child: Arc::new(Mutex::new(child)),
        pgid,
        port,
        shell_token,
    })
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
            handle.exit(0);
        }
    });
}

fn build_tray(
    app: &mut tauri::App,
    runtime: Arc<Runtime>,
) -> Result<(), Box<dyn std::error::Error>> {
    let status = MenuItem::with_id(app, "status", "Ready", false, None::<&str>)?;
    let open = MenuItem::with_id(app, "open", "Cuckoding", true, None::<&str>)?;
    let about = PredefinedMenuItem::about(app, Some("About Cuckoding"), None)?;
    let settings = MenuItem::with_id(app, "settings", "Settings", true, None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&status, &open, &about, &settings, &separator, &quit])?;
    let icon = Image::new_owned([0, 0, 0, 255].repeat(16 * 16), 16, 16);

    let menu_runtime = runtime.clone();
    TrayIconBuilder::new()
        .icon(icon)
        .icon_as_template(true)
        .tooltip("Cuckoding")
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(move |app, event| match event.id().as_ref() {
            "open" => open_browser(&menu_runtime, "/"),
            "settings" => open_browser(&menu_runtime, "/settings"),
            "quit" => {
                stop_runtime(&menu_runtime);
                app.exit(0);
            }
            _ => {}
        })
        .build(app)?;

    let monitor_runtime = runtime.clone();
    thread::spawn(move || loop {
        thread::sleep(Duration::from_secs(3));
        if monitor_runtime
            .child
            .lock()
            .unwrap()
            .try_wait()
            .ok()
            .flatten()
            .is_some()
        {
            let _ = status.set_text("Stopped unexpectedly");
            break;
        }
        if let Ok((200, body)) = http(
            monitor_runtime.port,
            "GET",
            "/shell/status",
            Some(&monitor_runtime.shell_token),
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

fn stop_runtime(runtime: &Runtime) {
    let _ = http(
        runtime.port,
        "POST",
        "/shell/shutdown",
        Some(&runtime.shell_token),
    );
    let deadline = Instant::now() + Duration::from_secs(3);
    while Instant::now() < deadline {
        if runtime
            .child
            .lock()
            .unwrap()
            .try_wait()
            .ok()
            .flatten()
            .is_some()
        {
            return;
        }
        thread::sleep(Duration::from_millis(50));
    }
    let mut child = runtime.child.lock().unwrap();
    kill_process_group(&mut child, runtime.pgid);
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
        && ready["version"].as_str() == Some("0.1.0")
    {
        Ok(())
    } else {
        Err("READY port mismatch".into())
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
    fn ready_requires_exact_prefix_and_port() {
        let input = Cursor::new(b"noise\nREADY {\"port\":43123,\"version\":\"0.1.0\"}\n".to_vec());
        assert!(wait_ready(input, 43123, Duration::from_millis(10)).is_ok());
    }

    #[test]
    fn ready_rejects_wrong_version() {
        let input = Cursor::new(b"READY {\"port\":43123,\"version\":\"wrong\"}\n".to_vec());
        assert!(wait_ready(input, 43123, Duration::from_millis(10)).is_err());
    }

    #[test]
    fn token_is_32_random_bytes_in_hex() {
        assert_eq!(random_token().unwrap().len(), 64);
    }
}
