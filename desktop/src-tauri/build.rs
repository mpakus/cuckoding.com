fn main() {
    use std::{path::PathBuf, process::Command};
    for path in ["keeper/main.swift", "keeper/entitlements.plist"] {
        println!("cargo:rerun-if-changed={path}");
    }
    let output = PathBuf::from(std::env::var_os("OUT_DIR").expect("Cargo output directory"));
    assert_eq!(
        std::env::var("TARGET").as_deref(),
        Ok("aarch64-apple-darwin"),
        "check keeper requires Apple Silicon"
    );
    let keeper = output.join("check-keeper");
    let status = Command::new("/usr/bin/xcrun")
        .args([
            "swiftc",
            "-target",
            "arm64-apple-macosx13.0",
            "-swift-version",
            "6",
            "-default-isolation",
            "MainActor",
            "-warnings-as-errors",
            "-O",
            "-module-cache-path",
        ])
        .arg(output.join("swift-cache"))
        .args(["keeper/main.swift", "-framework", "Virtualization", "-o"])
        .arg(&keeper)
        .status()
        .expect("Swift compiler required");
    assert!(status.success(), "check keeper compilation failed");
    let status = Command::new("/usr/bin/codesign")
        .args([
            "--force",
            "--sign",
            "-",
            "--entitlements",
            "keeper/entitlements.plist",
        ])
        .arg(&keeper)
        .status()
        .expect("keeper signing required");
    assert!(status.success(), "check keeper signing failed");
    println!("cargo:rustc-env=CCODING_CHECK_KEEPER={}", keeper.display());
    println!("cargo:rerun-if-env-changed=CCODING_BUILD_INFO_FILE");
    let info = match std::env::var("CCODING_BUILD_INFO_FILE") {
        Ok(path) => {
            println!("cargo:rerun-if-changed={path}");
            let value = std::fs::read_to_string(path).expect("build manifest required");
            assert!(value.len() <= 4096 && !value.contains(['\r', '\n', '\0']));
            value
        }
        Err(_) => "{}".to_owned(),
    };
    println!("cargo:rustc-env=CCODING_BUILD_INFO={info}");
    tauri_build::build()
}
