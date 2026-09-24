use std::{
    fs::{self, OpenOptions, Permissions},
    io::{BufRead, BufReader, Read, Write},
    net::TcpStream,
    os::unix::{
        fs::{OpenOptionsExt, PermissionsExt},
        process::CommandExt,
    },
    process::{Child, Command, Stdio},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    thread,
    time::{Duration, Instant},
};

use objc2_service_management::{SMAppService, SMAppServiceStatus};
use serde_json::Value;
use tauri::{
    image::Image,
    menu::{AboutMetadataBuilder, CheckMenuItem, Menu, MenuItem, PredefinedMenuItem},
    tray::TrayIconBuilder,
    ActivationPolicy, Manager,
};
use tauri_plugin_updater::UpdaterExt;

const VERSION: &str = env!("CARGO_PKG_VERSION");
const UPDATE_ENDPOINT: Option<&str> = option_env!("CUCKODING_UPDATE_ENDPOINT");
const UPDATE_PUBLIC_KEY: Option<&str> = option_env!("CUCKODING_UPDATER_PUBLIC_KEY");
const TRAY_ICON: &[u8] = include_bytes!("../icons/tray-icon.rgba");
static UPDATE_IN_PROGRESS: AtomicBool = AtomicBool::new(false);
static UPDATE_APPROVAL: Mutex<Option<String>> = Mutex::new(None);

struct Runtime {
    child: Mutex<Child>,
    pgid: i32,
    port: u16,
    shell_token: String,
    log_path: std::path::PathBuf,
    data_dir: std::path::PathBuf,
    release_path: std::path::PathBuf,
    safe_mode: bool,
}

struct RemoveOnDrop(std::path::PathBuf);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum LoginItemState {
    NotRegistered,
    Enabled,
    RequiresApproval,
    Unavailable,
}

impl Drop for RemoveOnDrop {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}

fn main() {
    block_shutdown_signals().expect("failed to install shutdown signal mask");

    let app = tauri::Builder::default()
        .plugin(
            tauri_plugin_updater::Builder::new()
                .pubkey(UPDATE_PUBLIC_KEY.unwrap_or_default())
                .build(),
        )
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
    let safe_mode = consume_safe_mode(&data_dir)?;

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

    let mut migrate = release_command(&release, &data_dir, port, &token_path, safe_mode);
    let migration_status = migrate
        .args(["eval", "Cuckoding.Release.migrate()"])
        .stdin(Stdio::null())
        .stdout(Stdio::from(stderr.try_clone()?))
        .stderr(Stdio::from(stderr.try_clone()?))
        .status()?;
    if !migration_status.success() {
        let _ = rollback_candidate(&release, &data_dir, port, "migration_failed");
        return Err("database migration failed".into());
    }

    let mut command = release_command(&release, &data_dir, port, &token_path, safe_mode);
    command
        .arg("start")
        // Host-only discovery hint; HOME and agent child environments stay isolated.
        .env("CUCKODING_RUNTIME_HOME", app.path().home_dir()?)
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
            let _ = rollback_candidate(&release, &data_dir, port, "candidate_health_failed");
            return Err(error);
        }
    };

    if matches!(
        http(port, "POST", "/shell/update/healthy", Some(&shell_token),),
        Ok((200, _))
    ) {
        remove_previous_app_backup(&data_dir);
    }

    Ok(Runtime {
        child: Mutex::new(child),
        pgid,
        port,
        shell_token,
        log_path,
        data_dir,
        release_path: release,
        safe_mode,
    })
}

fn release_command(
    release: &std::path::Path,
    data_dir: &std::path::Path,
    port: u16,
    token_path: &std::path::Path,
    safe_mode: bool,
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
    if safe_mode {
        command.env("CUCKODING_SAFE_MODE", "true");
    }
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
    let login_state = login_item_state();
    let (login_text, login_enabled, login_checked) = login_item_presentation(login_state);
    let login_item = CheckMenuItem::with_id(
        app,
        "login_item",
        login_text,
        login_enabled,
        login_checked,
        None::<&str>,
    )?;
    let update = MenuItem::with_id(
        app,
        "update",
        if update_configured() {
            "Check for Updates"
        } else {
            "Updates not configured"
        },
        update_configured(),
        None::<&str>,
    )?;
    let safe_mode =
        MenuItem::with_id(app, "safe_mode", "Restart in Safe Mode", true, None::<&str>)?;
    let diagnostics =
        MenuItem::with_id(app, "diagnostics", "Export Diagnostics", true, None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(
        app,
        &[
            &status,
            &open,
            &about,
            &settings,
            &logs,
            &login_item,
            &update,
            &diagnostics,
            &safe_mode,
            &separator,
            &quit,
        ],
    )?;
    let icon = tray_icon();

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
            "login_item" => {
                if toggle_login_item(&login_item).is_err() {
                    let _ = login_item.set_text("Launch at Login (Unavailable)");
                    let _ = login_item.set_checked(false);
                }
            }
            "update" => start_update(app.clone(), menu_runtime.clone(), update.clone()),
            "diagnostics" => {
                if export_diagnostics(&menu_runtime).is_err() {
                    let _ = quit_status.set_text("Diagnostics failed · open logs");
                }
            }
            "safe_mode" => restart_in_safe_mode(app, &menu_runtime),
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
                let mode = if runtime.safe_mode {
                    " · safe mode"
                } else {
                    ""
                };
                let _ =
                    status.set_text(format!("{runs} running · {attention} need attention{mode}"));
            }
        }
    });

    Ok(())
}

fn tray_icon() -> Image<'static> {
    Image::new(TRAY_ICON, 64, 64)
}

fn login_item_state() -> LoginItemState {
    // SAFETY: SMAppService is called from Tauri's main-thread menu setup/callback.
    let status = unsafe { SMAppService::mainAppService().status() };
    match status {
        SMAppServiceStatus::NotRegistered => LoginItemState::NotRegistered,
        SMAppServiceStatus::Enabled => LoginItemState::Enabled,
        SMAppServiceStatus::RequiresApproval => LoginItemState::RequiresApproval,
        _ => LoginItemState::Unavailable,
    }
}

fn login_item_presentation(state: LoginItemState) -> (&'static str, bool, bool) {
    match state {
        LoginItemState::NotRegistered => ("Launch at Login", true, false),
        LoginItemState::Enabled => ("Launch at Login", true, true),
        LoginItemState::RequiresApproval => ("Launch at Login (Approval Required)", true, false),
        LoginItemState::Unavailable => ("Launch at Login (Unavailable)", false, false),
    }
}

fn toggle_login_item(item: &CheckMenuItem<tauri::Wry>) -> Result<(), &'static str> {
    // SAFETY: mainAppService is the current signed application and this runs on
    // Tauri's main-thread menu callback.
    let service = unsafe { SMAppService::mainAppService() };
    match login_item_state() {
        LoginItemState::Enabled => unsafe { service.unregisterAndReturnError() }
            .map_err(|_| "login item unregister failed")?,
        LoginItemState::NotRegistered => unsafe { service.registerAndReturnError() }
            .map_err(|_| "login item registration failed")?,
        LoginItemState::RequiresApproval => unsafe { SMAppService::openSystemSettingsLoginItems() },
        LoginItemState::Unavailable => return Err("login item unavailable"),
    }

    let (text, enabled, checked) = login_item_presentation(login_item_state());
    item.set_text(text).map_err(|_| "login item menu failed")?;
    item.set_enabled(enabled)
        .map_err(|_| "login item menu failed")?;
    item.set_checked(checked)
        .map_err(|_| "login item menu failed")
}

fn export_diagnostics(runtime: &Runtime) -> Result<(), Box<dyn std::error::Error>> {
    let (status, body) = http(
        runtime.port,
        "POST",
        "/shell/diagnostics",
        Some(&runtime.shell_token),
    )?;
    if status != 200 {
        return Err(format!("diagnostics returned HTTP {status}").into());
    }

    let response = serde_json::from_str::<Value>(&body)?;
    let path = response["path"]
        .as_str()
        .ok_or("diagnostics response omitted path")?;
    let path = fs::canonicalize(path)?;
    let root = fs::canonicalize(runtime.data_dir.join("diagnostics"))?;
    if !path.starts_with(&root) || !path.is_file() {
        return Err("diagnostics path escaped application data".into());
    }

    let revealed = Command::new("/usr/bin/open")
        .args(["-R", path.to_str().ok_or("invalid diagnostics path")?])
        .status()?;
    if revealed.success() {
        Ok(())
    } else {
        Err("diagnostics reveal failed".into())
    }
}

fn update_configured() -> bool {
    UPDATE_ENDPOINT.is_some_and(|value| value.starts_with("https://"))
        && UPDATE_PUBLIC_KEY.is_some_and(|value| !value.is_empty())
}

fn start_update(app: tauri::AppHandle, runtime: Arc<Runtime>, status: MenuItem<tauri::Wry>) {
    if UPDATE_IN_PROGRESS.swap(true, Ordering::SeqCst) {
        return;
    }

    let _ = status.set_text("Checking for Updates…");
    tauri::async_runtime::spawn(async move {
        let result = install_update(&app, &runtime, &status).await;
        if let Err(error) = result {
            let _ = status.set_text(format!("Update failed · {error}"));
        }
        UPDATE_IN_PROGRESS.store(false, Ordering::SeqCst);
    });
}

async fn install_update(
    app: &tauri::AppHandle,
    runtime: &Runtime,
    status: &MenuItem<tauri::Wry>,
) -> Result<(), Box<dyn std::error::Error>> {
    let endpoint = UPDATE_ENDPOINT.ok_or("update endpoint is not configured")?;
    let endpoint = endpoint.parse()?;
    let updater = app
        .updater_builder()
        .endpoints(vec![endpoint])?
        .timeout(Duration::from_secs(30))
        .build()?;

    let Some(update) = updater.check().await? else {
        *UPDATE_APPROVAL.lock().unwrap() = None;
        status.set_text("Cuckoding is up to date")?;
        return Ok(());
    };

    let schema_change = update
        .raw_json
        .get("schema_change")
        .and_then(Value::as_bool)
        .unwrap_or(true);
    if !approve_update(&update.version.to_string()) {
        let impact = if schema_change {
            " · data backup required"
        } else {
            ""
        };
        status.set_text(format!("Install {}{impact} · click again", update.version))?;
        return Ok(());
    }

    status.set_text(format!("Downloading {}…", update.version))?;
    let bytes = update.download(|_, _| {}, || {}).await?;
    let prepare = serde_json::json!({
        "version": update.version,
        "schema_change": schema_change
    })
    .to_string();
    let (prepare_status, body) = http_json(
        runtime.port,
        "/shell/update/prepare",
        &runtime.shell_token,
        &prepare,
    )?;
    if prepare_status != 200 {
        return Err(format!("update preparation returned HTTP {prepare_status}").into());
    }

    let attempt_id = serde_json::from_str::<Value>(&body)?["attempt_id"]
        .as_str()
        .ok_or("update preparation omitted attempt id")?
        .to_owned();
    if let Err(error) = backup_current_app(&runtime.data_dir) {
        record_update_failure(runtime, &attempt_id, "application_backup_failed");
        return Err(error);
    }

    let installing = serde_json::json!({"attempt_id": attempt_id}).to_string();
    let (installing_status, _) = http_json(
        runtime.port,
        "/shell/update/installing",
        &runtime.shell_token,
        &installing,
    )?;
    if installing_status != 200 {
        record_update_failure(runtime, &attempt_id, "install_gate_failed");
        remove_previous_app_backup(&runtime.data_dir);
        return Err(format!("update install gate returned HTTP {installing_status}").into());
    }

    status.set_text(format!("Installing {}…", update.version))?;
    if let Err(error) = stop_runtime(runtime) {
        record_update_failure(runtime, &attempt_id, "runtime_shutdown_failed");
        remove_previous_app_backup(&runtime.data_dir);
        return Err(error);
    }

    if let Err(error) = update.install(bytes) {
        let _ = rollback_candidate(
            &runtime.release_path,
            &runtime.data_dir,
            runtime.port,
            "installation_failed",
        );
        app.exit(1);
        return Err(error.into());
    }

    if let Err(error) = open_current_app() {
        let _ = rollback_candidate(
            &runtime.release_path,
            &runtime.data_dir,
            runtime.port,
            "candidate_relaunch_failed",
        );
        app.exit(1);
        return Err(error);
    }

    app.exit(0);
    Ok(())
}

fn approve_update(version: &str) -> bool {
    let mut approved = UPDATE_APPROVAL.lock().unwrap();
    if approved.as_deref() == Some(version) {
        *approved = None;
        true
    } else {
        *approved = Some(version.to_owned());
        false
    }
}

fn record_update_failure(runtime: &Runtime, attempt_id: &str, reason: &str) {
    let body = serde_json::json!({"attempt_id": attempt_id, "reason": reason}).to_string();
    let _ = http_json(
        runtime.port,
        "/shell/update/failed",
        &runtime.shell_token,
        &body,
    );
}

fn consume_safe_mode(data_dir: &std::path::Path) -> std::io::Result<bool> {
    let marker = data_dir.join("safe-mode");
    match fs::symlink_metadata(&marker) {
        Ok(metadata)
            if metadata.file_type().is_file() && metadata.permissions().mode() & 0o077 == 0 =>
        {
            fs::remove_file(marker)?;
            Ok(true)
        }
        Ok(_) => Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "safe-mode marker must be a private regular file",
        )),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error),
    }
}

fn restart_in_safe_mode(app: &tauri::AppHandle, runtime: &Runtime) {
    let result = (|| -> Result<(), Box<dyn std::error::Error>> {
        let marker = runtime.data_dir.join("safe-mode");
        write_safe_mode_marker(&marker)?;
        stop_runtime(runtime)?;
        open_current_app()
    })();

    if result.is_ok() {
        app.exit(0);
    }
}

fn write_safe_mode_marker(marker: &std::path::Path) -> std::io::Result<()> {
    match fs::symlink_metadata(marker) {
        Ok(metadata)
            if metadata.file_type().is_file() && metadata.permissions().mode() & 0o077 == 0 =>
        {
            Ok(())
        }
        Ok(_) => Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "safe-mode marker must be a private regular file",
        )),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => OpenOptions::new()
            .create_new(true)
            .write(true)
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW)
            .open(marker)?
            .write_all(b"1"),
        Err(error) => Err(error),
    }
}

fn current_app_path() -> Result<std::path::PathBuf, Box<dyn std::error::Error>> {
    std::env::current_exe()?
        .ancestors()
        .find(|path| path.extension().is_some_and(|extension| extension == "app"))
        .map(std::path::Path::to_path_buf)
        .ok_or_else(|| "current executable is not inside an app bundle".into())
}

fn previous_app_path(data_dir: &std::path::Path) -> std::path::PathBuf {
    data_dir.join("updates/previous/Cuckoding.app")
}

fn backup_current_app(data_dir: &std::path::Path) -> Result<(), Box<dyn std::error::Error>> {
    let current = current_app_path()?;
    let backup = previous_app_path(data_dir);
    let parent = backup.parent().ok_or("missing update backup parent")?;
    let staging = parent.with_extension("staging");
    if staging.exists() {
        fs::remove_dir_all(&staging)?;
    }
    fs::create_dir_all(&staging)?;
    let staged_app = staging.join("Cuckoding.app");
    let status = Command::new("/usr/bin/ditto")
        .args([&current, &staged_app])
        .status()?;
    if !status.success() {
        let _ = fs::remove_dir_all(staging);
        return Err("application backup failed".into());
    }

    if parent.exists() {
        fs::remove_dir_all(parent)?;
    }
    fs::rename(staging, parent)?;
    Ok(())
}

fn remove_previous_app_backup(data_dir: &std::path::Path) {
    let backup = previous_app_path(data_dir);
    if backup.exists() {
        let _ = fs::remove_dir_all(backup.parent().unwrap_or(&backup));
    }
}

fn open_current_app() -> Result<(), Box<dyn std::error::Error>> {
    let status = Command::new("/usr/bin/open")
        .arg(current_app_path()?)
        .status()?;
    if status.success() {
        Ok(())
    } else {
        Err("application relaunch failed".into())
    }
}

fn rollback_candidate(
    release: &std::path::Path,
    data_dir: &std::path::Path,
    port: u16,
    reason: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let backup = previous_app_path(data_dir);
    let backup_metadata = fs::symlink_metadata(&backup)?;
    if !backup_metadata.file_type().is_dir() || !backup.join("Contents/MacOS").is_dir() {
        return Err("previous application backup is invalid".into());
    }

    let credential = data_dir.join(format!("rollback-{}", &random_token()?[..16]));
    let _credential_cleanup = RemoveOnDrop(credential.clone());
    write_runtime_credential(&credential)?;
    let expression = format!("Cuckoding.Release.rollback_pending({reason:?})");
    let rollback = release_command(release, data_dir, port, &credential, true)
        .args(["eval", &expression])
        .status()?;
    if !rollback.success() {
        return Err("data rollback failed".into());
    }

    let current = current_app_path()?;
    let replacement = current.with_extension("rollback.app");
    if replacement.exists() {
        fs::remove_dir_all(&replacement)?;
    }
    let copied = Command::new("/usr/bin/ditto")
        .args([&backup, &replacement])
        .status()?;
    if !copied.success() {
        return Err("application rollback copy failed".into());
    }
    fs::remove_dir_all(&current)?;
    fs::rename(replacement, &current)?;
    Command::new("/usr/bin/open").arg(current).spawn()?;
    Ok(())
}

fn write_runtime_credential(path: &std::path::Path) -> Result<(), Box<dyn std::error::Error>> {
    let session_secret = format!("{}{}", random_token()?, random_token()?);
    let bootstrap = random_token()?;
    Ok(OpenOptions::new()
        .create_new(true)
        .write(true)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW)
        .open(path)?
        .write_all(format!("{session_secret}\n{bootstrap}").as_bytes())?)
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
    http_request(port, method, path, bearer, None)
}

fn http_json(
    port: u16,
    path: &str,
    bearer: &str,
    body: &str,
) -> Result<(u16, String), Box<dyn std::error::Error>> {
    http_request(port, "POST", path, Some(bearer), Some(body))
}

fn http_request(
    port: u16,
    method: &str,
    path: &str,
    bearer: Option<&str>,
    body: Option<&str>,
) -> Result<(u16, String), Box<dyn std::error::Error>> {
    let mut stream = TcpStream::connect(("127.0.0.1", port))?;
    stream.set_read_timeout(Some(Duration::from_secs(3)))?;
    let body = body.unwrap_or_default();
    write!(
        stream,
        "{method} {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: {}\r\n",
        body.len()
    )?;
    if let Some(token) = bearer {
        write!(stream, "Authorization: Bearer {token}\r\n")?;
    }
    write!(stream, "\r\n{body}")?;

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
    fn tray_icon_is_a_small_template_image() {
        let icon = tray_icon();

        assert_eq!((icon.width(), icon.height()), (64, 64));
        assert!(icon.rgba().chunks_exact(4).any(|pixel| pixel[3] == 0));
        assert!(icon.rgba().chunks_exact(4).any(|pixel| pixel[3] > 0));
        assert!(icon
            .rgba()
            .chunks_exact(4)
            .all(|pixel| pixel[..3] == [0, 0, 0]));
    }

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

    #[test]
    fn safe_mode_marker_is_private_idempotent_and_consumed_once() {
        let directory =
            std::env::temp_dir().join(format!("cuckoding-safe-{}", random_token().unwrap()));
        fs::create_dir(&directory).unwrap();
        let marker = directory.join("safe-mode");

        write_safe_mode_marker(&marker).unwrap();
        write_safe_mode_marker(&marker).unwrap();
        assert_eq!(
            fs::metadata(&marker).unwrap().permissions().mode() & 0o077,
            0
        );
        assert!(consume_safe_mode(&directory).unwrap());
        assert!(!consume_safe_mode(&directory).unwrap());

        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn safe_mode_rejects_symlink_marker() {
        let directory =
            std::env::temp_dir().join(format!("cuckoding-safe-{}", random_token().unwrap()));
        fs::create_dir(&directory).unwrap();
        std::os::unix::fs::symlink("missing", directory.join("safe-mode")).unwrap();

        assert!(consume_safe_mode(&directory).is_err());

        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn update_install_requires_confirmation_for_the_exact_version() {
        *UPDATE_APPROVAL.lock().unwrap() = None;
        assert!(!approve_update("0.2.0"));
        assert!(!approve_update("0.3.0"));
        assert!(approve_update("0.3.0"));
        assert!(!approve_update("0.3.0"));
    }

    #[test]
    fn login_item_menu_reflects_native_service_status() {
        assert_eq!(
            login_item_presentation(LoginItemState::NotRegistered),
            ("Launch at Login", true, false)
        );
        assert_eq!(
            login_item_presentation(LoginItemState::Enabled),
            ("Launch at Login", true, true)
        );
        assert_eq!(
            login_item_presentation(LoginItemState::RequiresApproval),
            ("Launch at Login (Approval Required)", true, false)
        );
        assert_eq!(
            login_item_presentation(LoginItemState::Unavailable),
            ("Launch at Login (Unavailable)", false, false)
        );
    }

    #[test]
    fn native_login_item_status_is_queryable() {
        assert!(matches!(
            login_item_state(),
            LoginItemState::NotRegistered
                | LoginItemState::Enabled
                | LoginItemState::RequiresApproval
                | LoginItemState::Unavailable
        ));
    }
}
