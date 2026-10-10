mod arena_git;
mod connection;
mod cursor;
mod folder;
mod probe;
mod service;
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
    if args.first().is_some_and(|arg| arg == "--plan-codex-brief") {
        connection::plan_main(&args[1..]);
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
        if smoke().is_err() {
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
            let settings = MenuItem::with_id(app, "settings", "Settings", true, None::<&str>)?;
            let about = MenuItem::with_id(app, "about", "About Cuckoding", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&open, &settings, &about, &quit])?;
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
                                    "settings" => "/settings",
                                    "about" => "/about",
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

fn smoke() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let release = PathBuf::from(std::env::var_os("CCODING_RELEASE_DIR").ok_or("release required")?);
    let root =
        PathBuf::from(std::env::var_os("CCODING_DATA_DIR").ok_or("data directory required")?);
    let mut service = Service::launch(&release, &root, None)?;
    service.heartbeat()?;
    service.smoke_browser()?;
    let url = service.open_url("/")?;
    if !url.starts_with(&format!("http://127.0.0.1:{}/open?token=", service.port)) {
        return Err("invalid open URL".into());
    }
    service.shutdown()?;
    if std::net::TcpStream::connect(("127.0.0.1", service.port)).is_ok() {
        return Err("listener survived shutdown".into());
    }
    println!("PASS: bundled launch, bootstrap, browser cookie, handoff replay/origin refusal, heartbeat, graceful quit and listener cleanup");
    Ok(())
}
