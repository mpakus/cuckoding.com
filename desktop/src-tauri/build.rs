fn main() {
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
