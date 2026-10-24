//! Fixed, explicit upstream image installation; never starts a VM or runs project code.
mod archive;
mod store;
#[cfg(test)]
mod tests;
use crate::probe::{exited, private_directory, Group};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File, OpenOptions},
    io::{self, BufRead, Read, Seek, Write},
    os::unix::{
        fs::{MetadataExt, OpenOptionsExt},
        process::CommandExt,
    },
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::mpsc::{self, Receiver},
    thread,
    time::{Duration, Instant, SystemTime},
};
type Result<T> = std::result::Result<T, &'static str>;
const CONTRACT: &str = "isolated-check-image-v1";
const INPUTS: &str = include_str!("check_image/inputs.json");
const INIT: &str = include_str!("check_image/init");
const LAUNCH: &str = include_str!("check_image/launch");
const CONTROL: &str = include_str!("check_image/control.mjs");
const WORKER: &str = include_str!("check_image/worker.mjs");
const PROTOCOL: &str = include_str!("check_image/protocol.mjs");
fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
fn versions() -> Value {
    json!({"node":"24.22.1","npm":"11.12.1","elixir":"1.20.3","otp":"28.5.0.8"})
}
fn asset(store: &store::Store, input: &Value) -> Result<Vec<u8>> {
    let bytes = store.read(
        input["filename"].as_str().ok_or("unsupported_input")?,
        134_217_728,
    )?;
    if input["bytes"] != bytes.len() || input["sha256"] != hash(&bytes) {
        return Err("image_changed");
    }
    Ok(bytes)
}
fn spec() -> String {
    hash(
        [
            INPUTS.as_bytes(),
            INIT.as_bytes(),
            LAUNCH.as_bytes(),
            CONTROL.as_bytes(),
            WORKER.as_bytes(),
            PROTOCOL.as_bytes(),
            include_bytes!("check_image/archive.rs"),
            include_bytes!("check_image/store.rs"),
            include_bytes!("check_image.rs"),
        ]
        .concat()
        .as_slice(),
    )
}
fn key(value: &Value) -> Result<&str> {
    value
        .as_str()
        .filter(|v| {
            v.len() == 36
                && v.bytes().enumerate().all(|(i, b)| {
                    if [8, 13, 18, 23].contains(&i) {
                        b == b'-'
                    } else {
                        b.is_ascii_digit() || (b'a'..=b'f').contains(&b)
                    }
                })
        })
        .ok_or("invalid_request")
}
struct Installer {
    cancel: Receiver<()>,
    began: Instant,
    wall: SystemTime,
    cleaned: bool,
    journal: Option<File>,
}
impl Installer {
    fn record(&mut self, phase: &str, name: &str) -> Result<()> {
        if let Some(file) = &mut self.journal {
            writeln!(file, "{}", json!({"phase":phase,"input":name}))
                .and_then(|_| file.sync_all())
                .map_err(|_| "image_incomplete")?;
        }
        Ok(())
    }
    fn active(&self) -> Result<()> {
        if self.cancel.try_recv().is_ok() {
            return Err("cancelled");
        }
        if self.began.elapsed() >= Duration::from_secs(300)
            || self.wall.elapsed().unwrap_or(Duration::from_secs(300)) >= Duration::from_secs(300)
        {
            return Err("timeout");
        }
        Ok(())
    }
    fn command(&mut self, mut command: Command, output: File, input: Option<File>) -> Result<()> {
        self.active()?;
        let monitor = output.try_clone().map_err(|_| "image_incomplete")?;
        command
            .env_clear()
            .env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
            .env("LANG", "en_US.UTF-8")
            .stdin(input.map(Stdio::from).unwrap_or_else(Stdio::null))
            .stdout(output)
            .stderr(Stdio::null())
            .process_group(0);
        let child = command.spawn().map_err(|_| "download_failed")?;
        let mut owned = Group::new(child);
        let result = (|| {
            loop {
                self.active()?;
                if monitor.metadata().map_err(|_| "image_incomplete")?.len() > 134_217_728 {
                    return Err("image_limit");
                }
                if exited(&owned.0).map_err(|_| "cleanup_uncertain")? {
                    break;
                }
                thread::sleep(Duration::from_millis(20));
            }
            let mut info: libc::siginfo_t = unsafe { std::mem::zeroed() };
            // SAFETY: waitid observes only this owned unreaped child; info is correctly sized.
            let ok = unsafe {
                libc::waitid(
                    libc::P_PID,
                    owned.0.id(),
                    &mut info,
                    libc::WEXITED | libc::WNOHANG | libc::WNOWAIT,
                )
            } == 0
                && info.si_code == libc::CLD_EXITED
                && unsafe { info.si_status() } == 0;
            if ok {
                Ok(())
            } else {
                Err("download_failed")
            }
        })();
        let cleaned = owned.finish();
        self.cleaned &= cleaned;
        if cleaned {
            result
        } else {
            Err("cleanup_uncertain")
        }
    }
    fn run(&mut self, home: &Path, request: &Value, verify: bool) -> Result<Value> {
        self.active()?;
        if !request.as_object().is_some_and(|v| v.len() == 2) {
            return Err("invalid_request");
        }
        let key = key(&request["key"])?;
        if !verify && request["contract"] != CONTRACT {
            return Err("invalid_request");
        }
        let store = store::Store::open(home, key, !verify)?;
        store.current()?;
        let spec = spec();
        if verify {
            let receipt: Value = serde_json::from_slice(&store.read("receipt.json", 8192)?)
                .map_err(|_| "image_changed")?;
            let manifest = store.read("manifest.json", 65536)?;
            let description: Value =
                serde_json::from_slice(&manifest).map_err(|_| "image_changed")?;
            let intent = json!({"contract":CONTRACT,"key":key,"spec_sha256":spec}).to_string();
            if store.read("intent.json", 8192)? != intent.as_bytes()
                || !receipt.as_object().is_some_and(|r| r.len() == 12)
                || receipt["cleanup_verified"] != true
                || !description.as_object().is_some_and(|r| r.len() == 7)
                || receipt["intent_sha256"] != hash(intent.as_bytes())
                || description["key"] != key
                || description["contract"] != CONTRACT
                || receipt["toolchains"] != versions()
                || description["files"]
                    .as_u64()
                    .is_none_or(|n| n == 0 || n > 12000)
                || description["expanded_bytes"]
                    .as_u64()
                    .is_none_or(|n| n == 0 || n > 536_870_912)
                || request["image"] != receipt
                || receipt["key"] != key
                || receipt["spec_sha256"] != spec
                || receipt["contract"] != CONTRACT
                || receipt["status"] != "check_image_prepared"
                || receipt["manifest_sha256"] != hash(&manifest)
                || description["spec_sha256"] != spec
                || description["inputs"] != serde_json::from_str::<Value>(INPUTS).unwrap()
                || description["toolchains"] != versions()
            {
                return Err("image_changed");
            }
            for (name, prefix) in [("kernel", "kernel"), ("ramdisk.cpio.gz", "ramdisk")] {
                self.active()?;
                let bytes = store.read(name, 134_217_728)?;
                if receipt[format!("{prefix}_sha256")] != hash(&bytes)
                    || receipt[format!("{prefix}_bytes")] != bytes.len()
                {
                    return Err("image_changed");
                }
            }
            store.current()?;
            self.active()?;
            let mut result = receipt;
            result["status"] = json!("check_image_verified");
            return Ok(result);
        }
        self.active()?;
        store.write(
            "intent.json",
            json!({"contract":CONTRACT,"key":key,"spec_sha256":spec})
                .to_string()
                .as_bytes(),
        )?;
        self.journal = Some(store.create("progress.jsonl")?);
        let inputs: Vec<Value> = serde_json::from_str(INPUTS).map_err(|_| "unsupported_input")?;
        for input in &inputs {
            self.active()?;
            let name = input["filename"].as_str().ok_or("unsupported_input")?;
            if name.contains('/') || name.starts_with('.') {
                return Err("unsupported_input");
            }
            let url = input["url"].as_str().ok_or("unsupported_input")?;
            if !url.starts_with("https://") {
                return Err("unsupported_input");
            }
            self.record("download", name)?;
            let mut curl = Command::new("/usr/bin/curl");
            curl.args([
                "--disable",
                "--fail",
                "--location",
                "--globoff",
                "--proto",
                "=https",
                "--proto-redir",
                "=https",
                "--tlsv1.2",
                "--connect-timeout",
                "10",
                "--max-time",
                "60",
                "--silent",
                "--show-error",
                "--max-filesize",
                &input["bytes"]
                    .as_u64()
                    .ok_or("unsupported_input")?
                    .to_string(),
                url,
            ]);
            self.command(curl, store.create(name)?, None)?;
            asset(&store, input)?;
        }
        let iso_input = inputs
            .iter()
            .find(|i| i["filename"] == "alpine-virt-3.24.3-aarch64.iso")
            .ok_or("unsupported_input")?;
        let mut iso = store.reader("alpine-virt-3.24.3-aarch64.iso")?;
        let before = iso.metadata().map_err(|_| "image_changed")?;
        let mut digest = Sha256::new();
        let count = io::copy(&mut (&mut iso).take(134_217_729), &mut digest)
            .map_err(|_| "image_changed")?;
        if iso_input["bytes"] != count || iso_input["sha256"] != format!("{:x}", digest.finalize())
        {
            return Err("image_changed");
        }
        iso.rewind().map_err(|_| "image_changed")?;
        let mut tar = Command::new("/usr/bin/tar");
        self.record("kernel", "alpine-virt-3.24.3-aarch64.iso")?;
        store.current()?;
        tar.args(["-xOf", "-", "boot/vmlinuz-virt"]);
        self.command(
            tar,
            store.create("kernel.efi")?,
            Some(iso.try_clone().map_err(|_| "image_changed")?),
        )?;
        let after = iso.metadata().map_err(|_| "image_changed")?;
        if before.len() != after.len()
            || before.mtime() != after.mtime()
            || before.mtime_nsec() != after.mtime_nsec()
            || before.ctime() != after.ctime()
            || before.ctime_nsec() != after.ctime_nsec()
        {
            return Err("image_changed");
        }
        let kernel = archive::kernel(&store.read("kernel.efi", 134_217_728)?)?;
        store.write("kernel", &kernel)?;
        let mut image = archive::Image::new();
        self.record("compose", "alpine-minirootfs-3.24.3-aarch64.tar.gz")?;
        image.tar(
            &asset(
                &store,
                inputs
                    .iter()
                    .find(|i| i["filename"] == "alpine-minirootfs-3.24.3-aarch64.tar.gz")
                    .ok_or("unsupported_input")?,
            )?,
            true,
            &|| self.active(),
        )?;
        for input in &inputs {
            self.active()?;
            let name = input["filename"].as_str().unwrap();
            self.record("compose", name)?;
            if name.ends_with(".apk") {
                image.tar(&asset(&store, input)?, false, &|| self.active())?;
            }
            if name.ends_with(".zip") {
                image.zip(asset(&store, input)?, &|| self.active())?;
            }
        }
        self.record("compose", "production-entry")?;
        let (files, expanded) = image.finish(&store, &spec, &|| self.active())?;
        let ramdisk = store.read("ramdisk.cpio.gz", 134_217_728)?;
        let manifest = json!({"contract":CONTRACT,"key":key,"spec_sha256":spec,"inputs":inputs,
            "toolchains":versions(),"files":files,"expanded_bytes":expanded})
        .to_string()
        .into_bytes();
        store.write("manifest.json", &manifest)?;
        let intent = json!({"contract":CONTRACT,"key":key,"spec_sha256":spec}).to_string();
        let result = json!({"status":"check_image_prepared","contract":CONTRACT,"key":key,"spec_sha256":spec,"intent_sha256":hash(intent.as_bytes()),"cleanup_verified":true,
            "kernel_sha256":hash(&kernel),"kernel_bytes":kernel.len(),"ramdisk_sha256":hash(&ramdisk),
            "ramdisk_bytes":ramdisk.len(),"manifest_sha256":hash(&manifest),"toolchains":versions()});
        store.current()?;
        self.active()?;
        store.write("receipt.json", result.to_string().as_bytes())?;
        self.record("complete", "image")?;
        store.current()?;
        self.active()?;
        Ok(result)
    }
}
pub fn main(verify: bool) {
    let mut text = String::new();
    let request = io::stdin()
        .lock()
        .take(8193)
        .read_line(&mut text)
        .ok()
        .filter(|_| text.len() <= 8192 && text.ends_with('\n'))
        .and_then(|_| serde_json::from_str::<Value>(&text).ok())
        .unwrap_or(Value::Null);
    let (tx, cancel) = mpsc::channel();
    thread::spawn(move || {
        let _ = io::stdin().read(&mut [0]);
        let _ = tx.send(());
    });
    let mut installer = Installer {
        cancel,
        began: Instant::now(),
        wall: SystemTime::now(),
        cleaned: true,
        journal: None,
    };
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_default();
    let mut result = installer
        .run(&home, &request, verify)
        .unwrap_or_else(|status| json!({"status":status,"contract":CONTRACT,"key":request["key"]}));
    result["cleanup_verified"] = json!(installer.cleaned);
    let _ = writeln!(io::stdout(), "{result}");
}
