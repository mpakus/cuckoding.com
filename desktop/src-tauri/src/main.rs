mod arena_git;
mod build_info;
mod codex_versions;
mod connection;
mod cursor;
mod folder;
mod isolation;
mod power;
mod probe;
mod project_checks;
mod service;
mod task_closure;
use service::Service;
use std::{
    path::PathBuf,
    process::Command,
    sync::{Arc, Mutex},
    time::Duration,
};
use tauri::{
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
    Manager, RunEvent,
};

fn main() {
    // Restrict files made by the release and its children, including SQLite WAL.
    unsafe {
        libc::umask(0o077);
    }
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args.as_slice() == ["--build-info"] {
        println!("{}", build_info::public());
        return;
    }
    if args.as_slice() == ["--inspect-provider-closure"] {
        task_closure::main();
        return;
    }
    if args.as_slice() == ["--battle-checks"] {
        project_checks::main();
        return;
    }
    if args.first().is_some_and(|a| a == "--execute-battle-check") {
        project_checks::execute(&args[1..]);
        return;
    }
    if args.first().is_some_and(|arg| arg == "--arena-git") {
        arena_git::main(&args[1..]);
        return;
    }
    if args.as_slice() == ["--choose-arena-folder"] {
        folder::main();
        return;
    }
    if let Some(operation) = args.first().and_then(|arg| match arg.as_str() {
        "--probe-cursor" => Some(cursor::Operation::Probe),
        "--inspect-cursor" => Some(cursor::Operation::Inspect),
        "--login-cursor" => Some(cursor::Operation::Login),
        "--logout-cursor" => Some(cursor::Operation::Logout),
        _ => None,
    }) {
        cursor::main(&args[1..], operation);
        return;
    }
    if args.first().is_some_and(|arg| arg == "--probe-codex") {
        probe::main(&args[1..]);
        return;
    }
    if args
        .first()
        .is_some_and(|arg| arg == "--check-codex-isolation")
    {
        isolation::main(&args[1..]);
        return;
    }
    if args.first().is_some_and(|arg| arg == "--plan-codex-brief") {
        connection::plan_main(&args[1..]);
        return;
    }
    if args.first().is_some_and(|arg| arg == "--run-cursor-task") {
        cursor::task::main(&args[1..]);
        return;
    }
    if args.first().is_some_and(|arg| arg == "--plan-cursor-brief") {
        cursor::task::plan_main(&args[1..]);
        return;
    }
    if args.first().is_some_and(|arg| arg == "--run-codex-task") {
        connection::task_main(&args[1..]);
        return;
    }
    if args.first().is_some_and(|arg| arg == "--check-codex-model") {
        connection::model_main(&args[1..]);
        return;
    }
    if args.first().is_some_and(|arg| arg == "--inspect-codex") {
        connection::main(&args[1..], connection::Operation::Inspect);
        return;
    }
    if args.first().is_some_and(|arg| arg == "--login-codex") {
        connection::main(&args[1..], connection::Operation::Login);
        return;
    }
    if args.first().is_some_and(|arg| arg == "--logout-codex") {
        connection::main(&args[1..], connection::Operation::Logout);
        return;
    }
    if std::env::args().any(|arg| arg == "--smoke-test") {
        if smoke(args.iter().any(|arg| arg == "--wait-for-input")).is_err() {
            eprintln!("Cuckoding shell smoke test failed.");
            std::process::exit(1);
        }
        return;
    }
    let app = tauri::Builder::default()
        .setup(|app| {
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);
            let release = app.path().resource_dir()?.join("release");
            let root = data_root()?;
            let home = std::env::var("HOME").ok();
            let service = Service::launch(&release, &root, home.as_deref())
                .map_err(|error| -> Box<dyn std::error::Error> { error.to_string().into() })?;
            let shared = Arc::new(Mutex::new(service));
            app.manage(shared.clone());
            let open = MenuItem::with_id(app, "open", "Open Cuckoding", true, None::<&str>)?;
            let agents = MenuItem::with_id(app, "agents", "Agents", true, None::<&str>)?;
            let settings = MenuItem::with_id(app, "settings", "Settings", true, None::<&str>)?;
            let about = MenuItem::with_id(app, "about", "About Cuckoding", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&open, &agents, &settings, &about, &quit])?;
            TrayIconBuilder::new()
                .icon(tauri::include_image!("icons/tray.png"))
                .icon_as_template(true)
                .tooltip("Cuckoding")
                .menu(&menu)
                .on_menu_event(|app, event| {
                    let shared = app.state::<Arc<Mutex<Service>>>();
                    if let Ok(mut service) = shared.lock() {
                        match event.id.as_ref() {
                            "quit" => {
                                let _ = service.shutdown();
                                app.exit(0);
                            }
                            id => {
                                let view = match id {
                                    "agents" => "/agents",
                                    "settings" | "about" => "/settings",
                                    _ => "/",
                                };
                                if let Ok(url) = service.open_url(view) {
                                    let _ = Command::new("/usr/bin/open").arg(url).spawn();
                                }
                            }
                        }
                    };
                })
                .build(app)?;
            // Opening the app should reveal its workspace, including on first launch.
            if let Ok(service) = shared.lock() {
                if let Ok(url) = service.open_url("/") {
                    let _ = Command::new("/usr/bin/open").arg(url).spawn();
                }
            }
            let handle = app.handle().clone();
            std::thread::spawn(move || loop {
                std::thread::sleep(Duration::from_secs(5));
                if shared
                    .lock()
                    .map_or(true, |mut service| service.heartbeat().is_err())
                {
                    handle.exit(1);
                    break;
                }
            });
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("Cuckoding could not start its local workspace.");
    app.run(|app, event| {
        if let RunEvent::ExitRequested { api, code, .. } = event {
            if code.is_none() {
                api.prevent_exit();
                if let Ok(mut service) = app.state::<Arc<Mutex<Service>>>().lock() {
                    let _ = service.shutdown();
                }
                app.exit(0);
            }
        }
    });
}

fn data_root() -> Result<PathBuf, Box<dyn std::error::Error>> {
    if let Some(path) = std::env::var_os("CCODING_DATA_DIR") {
        return Ok(PathBuf::from(path));
    }
    let home = std::env::var_os("HOME").ok_or("Home directory unavailable")?;
    Ok(PathBuf::from(home).join("Library/Application Support/CCoding Rebuild"))
}

type SmokeResult<T> = Result<T, Box<dyn std::error::Error + Send + Sync>>;

fn smoke(hold: bool) -> SmokeResult<()> {
    let release = PathBuf::from(std::env::var_os("CCODING_RELEASE_DIR").ok_or("release required")?);
    let root =
        PathBuf::from(std::env::var_os("CCODING_DATA_DIR").ok_or("data directory required")?);
    let home = std::env::var("HOME").ok();
    let mut service = Service::launch(&release, &root, if hold { home.as_deref() } else { None })?;
    service.heartbeat()?;
    service.smoke_browser()?;
    let url = service.open_url("/")?;
    if !url.starts_with(&format!("http://127.0.0.1:{}/open?token=", service.port)) {
        return Err("invalid open URL".into());
    }
    let wait = if hold {
        hold_smoke(&mut service)
    } else {
        Ok(())
    };
    service.shutdown()?;
    wait?;
    if std::net::TcpStream::connect(("127.0.0.1", service.port)).is_ok() {
        return Err("listener survived shutdown".into());
    }
    println!("PASS: bundled launch, bootstrap, browser cookie, handoff replay/origin refusal, heartbeat, graceful quit and listener cleanup");
    Ok(())
}

fn hold_smoke(service: &mut Service) -> SmokeResult<()> {
    use std::io::{Read, Write};
    let (sender, receiver) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        if std::io::stdin().read(&mut [0]).is_ok() {
            let _ = sender.send(());
        }
    });
    writeln!(std::io::stdout(), "CCODING_SMOKE_HELD")?;
    std::io::stdout().flush()?;
    wait_smoke_controller(
        receiver,
        || service.heartbeat(),
        Duration::from_secs(90),
        Duration::from_secs(5),
    )
}

fn wait_smoke_controller(
    receiver: std::sync::mpsc::Receiver<()>,
    mut heartbeat: impl FnMut() -> SmokeResult<()>,
    limit: Duration,
    interval: Duration,
) -> SmokeResult<()> {
    let deadline = std::time::Instant::now() + limit;
    loop {
        let remaining = deadline.saturating_duration_since(std::time::Instant::now());
        if remaining.is_zero() {
            return Err("smoke controller timed out".into());
        }
        match receiver.recv_timeout(remaining.min(interval)) {
            Ok(()) => return Ok(()),
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => heartbeat()?,
            Err(_) => return Err("smoke controller unavailable".into()),
        }
    }
}

#[cfg(test)]
mod smoke_tests {
    use super::*;

    #[test]
    fn held_smoke_releases_on_input_and_heartbeats_without_authority() {
        let (sender, receiver) = std::sync::mpsc::channel();
        let mut calls = 0;
        wait_smoke_controller(
            receiver,
            || {
                calls += 1;
                sender.send(())?;
                Ok(())
            },
            Duration::from_secs(5),
            Duration::from_millis(1),
        )
        .unwrap();
        assert_eq!(calls, 1);
    }

    #[test]
    fn held_smoke_refuses_timeout_controller_loss_and_heartbeat_failure() {
        let (sender, receiver) = std::sync::mpsc::channel();
        assert!(
            wait_smoke_controller(receiver, || Ok(()), Duration::ZERO, Duration::from_secs(5))
                .is_err()
        );
        drop(sender);
        let (sender, receiver) = std::sync::mpsc::channel();
        drop(sender);
        assert!(wait_smoke_controller(
            receiver,
            || Ok(()),
            Duration::from_secs(5),
            Duration::from_secs(5)
        )
        .is_err());
        let (_sender, receiver) = std::sync::mpsc::channel();
        assert!(wait_smoke_controller(
            receiver,
            || Err("fixture".into()),
            Duration::from_secs(5),
            Duration::from_millis(1)
        )
        .is_err());
    }
}
