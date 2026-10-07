//! Fixed native directory selection; never reads project contents or runs Git.
use objc2::MainThreadMarker;
use objc2_app_kit::{NSApplication, NSApplicationActivationPolicy, NSModalResponseOK, NSOpenPanel};
use objc2_foundation::NSString;
use serde_json::{json, Value};
use std::{io::Read, path::Path, time::Duration};

pub fn main() {
    // This helper owns no children. Parent loss/cancel/deadline exits the entire
    // helper, including its modal window; it never signals another process.
    // Erlang's port launcher may already make this a session/group leader.
    if unsafe { libc::getpgrp() != libc::getpid() && libc::setpgid(0, 0) != 0 } {
        println!("{}", json!({"status": "invalid_folder"}));
        return;
    }
    std::thread::spawn(|| {
        let _ = std::io::stdin().read(&mut [0]);
        std::process::exit(0);
    });
    std::thread::spawn(|| {
        std::thread::sleep(Duration::from_secs(120));
        println!("{}", json!({"status": "timeout"}));
        std::process::exit(0);
    });

    let mtm = MainThreadMarker::new().expect("native chooser requires the main thread");
    let app = NSApplication::sharedApplication(mtm);
    app.setActivationPolicy(NSApplicationActivationPolicy::Accessory);
    let panel = NSOpenPanel::openPanel(mtm);
    panel.setTitle(Some(&NSString::from_str("Choose an Arena folder")));
    panel.setMessage(Some(&NSString::from_str(
        "Choose an existing project folder. Cuckoding will preview it before registration.",
    )));
    panel.setPrompt(Some(&NSString::from_str("Choose folder")));
    panel.setCanChooseDirectories(true);
    panel.setCanChooseFiles(false);
    panel.setAllowsMultipleSelection(false);
    panel.setCanCreateDirectories(false);
    panel.setCanDownloadUbiquitousContents(false);
    panel.setCanResolveUbiquitousConflicts(false);
    // Supported by the bundle's macOS 13 minimum, unlike activate() (macOS 14).
    #[allow(deprecated)]
    app.activateIgnoringOtherApps(true);
    let result = if panel.runModal() == NSModalResponseOK {
        panel
            .URL()
            .and_then(|url| url.path())
            .map(|path| selection(Path::new(&path.to_string())))
            .unwrap_or_else(|| json!({"status": "invalid_folder"}))
    } else {
        json!({"status": "cancelled"})
    };
    println!("{result}");
}

fn selection(path: &Path) -> Value {
    match path.canonicalize() {
        Ok(path) if path.is_dir() => match path.to_str() {
            Some(path) if path.len() <= 4096 && !path.chars().any(char::is_control) => {
                json!({"status": "selected", "path": path})
            }
            _ => json!({"status": "invalid_folder"}),
        },
        _ => json!({"status": "invalid_folder"}),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn selection_is_canonical_and_does_not_accept_files_or_missing_paths() {
        let root = std::env::temp_dir().join(format!("cuckoding-folder-{}", std::process::id()));
        std::fs::create_dir(&root).unwrap();
        let alias = root.join("alias");
        std::os::unix::fs::symlink(&root, &alias).unwrap();
        assert_eq!(selection(&alias), selection(&root));
        assert_eq!(selection(&root)["status"], "selected");
        assert_eq!(selection(&root.join("missing"))["status"], "invalid_folder");
        let file = root.join("document.md");
        std::fs::write(&file, "unchanged").unwrap();
        assert_eq!(selection(&file)["status"], "invalid_folder");
        assert_eq!(std::fs::read_to_string(&file).unwrap(), "unchanged");
        std::fs::remove_dir_all(root).unwrap();
    }
}
