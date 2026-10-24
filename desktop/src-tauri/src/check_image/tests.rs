use super::*;
use std::{
    os::unix::fs::{symlink, DirBuilderExt, PermissionsExt},
    sync::atomic::{AtomicUsize, Ordering},
};

static NEXT: AtomicUsize = AtomicUsize::new(0);
fn fixture() -> (PathBuf, Receiver<()>) {
    let root = std::env::temp_dir().canonicalize().unwrap().join(format!(
        "cuckoding-check-image-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    fs::DirBuilder::new().mode(0o700).create(&root).unwrap();
    let home = root.join("runtime-home");
    fs::DirBuilder::new().mode(0o700).create(&home).unwrap();
    let (_tx, rx) = mpsc::channel();
    (home, rx)
}
fn installer(cancel: Receiver<()>) -> Installer {
    Installer {
        cancel,
        began: Instant::now(),
        wall: SystemTime::now(),
        cleaned: true,
        journal: None,
    }
}
const KEY: &str = "00000000-0000-4000-8000-000000000001";

#[test]
fn image_inputs_and_request_scope_are_fixed_without_network_fallbacks() {
    let inputs: Vec<Value> = serde_json::from_str(INPUTS).unwrap();
    assert_eq!(inputs.len(), 24);
    let mut names = std::collections::BTreeSet::new();
    for input in inputs {
        let name = input["filename"].as_str().unwrap();
        assert!(names.insert(name.to_owned()) && !name.contains('/') && !name.starts_with('.'));
        assert!(input["url"].as_str().unwrap().starts_with("https://"));
        assert!(input["bytes"]
            .as_u64()
            .is_some_and(|n| n > 0 && n <= 134_217_728));
        assert_eq!(input["sha256"].as_str().unwrap().len(), 64);
    }
    let (home, rx) = fixture();
    let mut work = installer(rx);
    for request in [
        json!({"key":"../escape","contract":CONTRACT}),
        json!({"key":KEY,"contract":"foreign"}),
        json!({"key":KEY,"contract":CONTRACT,"url":"https://foreign.invalid/"}),
    ] {
        assert_eq!(work.run(&home, &request, false), Err("invalid_request"));
    }
    assert!(!home.join("check-images").exists());
    let (tx, rx) = mpsc::channel();
    tx.send(()).unwrap();
    assert_eq!(
        installer(rx).run(&home, &json!({"key":KEY,"contract":CONTRACT}), false),
        Err("cancelled")
    );
    assert!(!home.join("check-images").exists());
    assert_eq!(spec().len(), 64);
}

#[test]
fn image_storage_is_exclusive_private_descriptor_bound_and_link_safe() {
    let (home, _) = fixture();
    let store = store::Store::open(&home, KEY, true).unwrap();
    store.write("data", b"original").unwrap();
    assert_eq!(store.read("data", 8).unwrap(), b"original");
    assert_eq!(store.read("data", 7), Err("image_changed"));
    assert!(store.write("data", b"overwrite").is_err());
    assert!(matches!(
        store::Store::open(&home, KEY, true),
        Err("image_exists")
    ));
    let path = home.join("check-images").join(KEY);
    fs::hard_link(path.join("data"), path.join("hard")).unwrap();
    assert_eq!(store.read("data", 8), Err("image_changed"));
    fs::remove_file(path.join("hard")).unwrap();
    symlink(path.join("data"), path.join("link")).unwrap();
    assert_eq!(store.read("link", 8), Err("image_changed"));
    fs::set_permissions(path.join("data"), fs::Permissions::from_mode(0o644)).unwrap();
    assert_eq!(store.read("data", 8), Err("image_changed"));
    let moved = home.join("retained");
    fs::rename(&path, &moved).unwrap();
    fs::DirBuilder::new().mode(0o700).create(&path).unwrap();
    assert_eq!(store.current(), Err("image_changed"));
    assert_eq!(fs::read(moved.join("data")).unwrap(), b"original");
}

#[test]
fn retained_image_verification_binds_exact_scope_hashes_and_never_repairs() {
    let (home, rx) = fixture();
    let store = store::Store::open(&home, KEY, true).unwrap();
    let spec = spec();
    let intent = json!({"contract":CONTRACT,"key":KEY,"spec_sha256":spec}).to_string();
    store.write("intent.json", intent.as_bytes()).unwrap();
    store.write("kernel", b"kernel").unwrap();
    store.write("ramdisk.cpio.gz", b"ramdisk").unwrap();
    let manifest=json!({"contract":CONTRACT,"key":KEY,"spec_sha256":spec,
        "inputs":serde_json::from_str::<Value>(INPUTS).unwrap(),"toolchains":versions(),"files":1,"expanded_bytes":1}).to_string();
    store.write("manifest.json", manifest.as_bytes()).unwrap();
    let receipt = json!({"status":"check_image_prepared","contract":CONTRACT,"key":KEY,"spec_sha256":spec,
        "intent_sha256":hash(intent.as_bytes()),"kernel_sha256":hash(b"kernel"),"kernel_bytes":6,
        "ramdisk_sha256":hash(b"ramdisk"),"ramdisk_bytes":7,"manifest_sha256":hash(manifest.as_bytes()),
        "toolchains":versions(),"cleanup_verified":true});
    store
        .write("receipt.json", receipt.to_string().as_bytes())
        .unwrap();
    let request = json!({"key":KEY,"image":receipt});
    let mut work = installer(rx);
    let verified = work.run(&home, &request, true).unwrap();
    assert_eq!(verified["status"], "check_image_verified");
    let original = store.read("receipt.json", 8192).unwrap();
    assert!(work.run(&home, &request, true).is_ok());
    assert_eq!(store.read("receipt.json", 8192).unwrap(), original);
    let path = home.join("check-images").join(KEY);
    fs::write(path.join("kernel"), b"tamper").unwrap();
    assert_eq!(work.run(&home, &request, true), Err("image_changed"));
    fs::write(path.join("kernel"), b"kernel").unwrap();
    fs::remove_file(path.join("intent.json")).unwrap();
    assert_eq!(work.run(&home, &request, true), Err("image_changed"));
    assert!(!path.join("intent.json").exists());
}

#[test]
fn child_cancellation_closes_the_owned_download_group() {
    let (home, _) = fixture();
    let store = store::Store::open(&home, KEY, true).unwrap();
    let (tx, rx) = mpsc::channel();
    let mut work = installer(rx);
    let mut sleep = Command::new("/bin/sleep");
    sleep.arg("20");
    thread::spawn(move || {
        thread::sleep(Duration::from_millis(100));
        tx.send(()).unwrap();
    });
    assert_eq!(
        work.command(sleep, store.create("output").unwrap(), None),
        Err("cancelled")
    );
    assert!(work.cleaned && work.began.elapsed() < Duration::from_secs(3));
}

#[test]
fn run_clones_are_exclusive_independent_private_files_and_preserve_the_image() {
    let (home, _) = fixture();
    let image = store::Store::open(&home, KEY, true).unwrap();
    image.write("kernel", b"original").unwrap();
    let run = store::Store::run(&home, KEY).unwrap();
    let mut copy = run
        .clone_file(&image.reader("kernel").unwrap(), "kernel")
        .unwrap();
    copy.write_all(b"-append").unwrap();
    copy.sync_all().unwrap();
    assert_eq!(image.read("kernel", 100).unwrap(), b"original");
    assert_eq!(run.read("kernel", 100).unwrap(), b"original-append");
    assert!(run
        .clone_file(&image.reader("kernel").unwrap(), "kernel")
        .is_err());
    image.current().unwrap();
    run.current().unwrap();
}

fn tar_gzip(path: &str, kind: tar::EntryType, data: &[u8]) -> Vec<u8> {
    let mut header = tar::Header::new_gnu();
    header.set_entry_type(kind);
    header.set_size(data.len() as u64);
    header.set_mode(0o6755);
    header.as_mut_bytes()[..path.len()].copy_from_slice(path.as_bytes());
    header.set_cksum();
    let mut archive = tar::Builder::new(Vec::new());
    archive.append(&header, data).unwrap();
    let bytes = archive.into_inner().unwrap();
    let mut gzip = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
    gzip.write_all(&bytes).unwrap();
    gzip.finish().unwrap()
}

#[test]
fn archive_paths_special_entries_cancellation_and_parent_collisions_refuse() {
    for path in ["/absolute", "../escape", "x/../escape", "x//bad", "x\\bad"] {
        let mut image = archive::Image::new();
        assert!(
            image
                .tar(
                    &tar_gzip(path, tar::EntryType::Regular, b"data"),
                    false,
                    &|| Ok(())
                )
                .is_err(),
            "{path}"
        );
    }
    let mut image = archive::Image::new();
    assert_eq!(
        image.tar(&tar_gzip("fifo", tar::EntryType::Fifo, b""), false, &|| Ok(
            ()
        )),
        Err("unsupported_input")
    );
    assert_eq!(
        image.tar(
            &tar_gzip("x", tar::EntryType::Regular, b"one"),
            false,
            &|| Err("cancelled")
        ),
        Err("cancelled")
    );
    image
        .tar(
            &tar_gzip("x", tar::EntryType::Regular, b"one"),
            false,
            &|| Ok(()),
        )
        .unwrap();
    assert_eq!(
        image.tar(
            &tar_gzip("x", tar::EntryType::Regular, b"two"),
            false,
            &|| Ok(())
        ),
        Err("unsupported_input")
    );
    image
        .tar(
            &tar_gzip("x/y", tar::EntryType::Regular, b"data"),
            false,
            &|| Ok(()),
        )
        .unwrap();
    let (home, _) = fixture();
    let store = store::Store::open(&home, KEY, true).unwrap();
    assert_eq!(
        image.finish(&store, &spec(), &|| Ok(())),
        Err("unsupported_input")
    );
    assert!(!home
        .join("check-images")
        .join(KEY)
        .join("ramdisk.cpio.gz")
        .exists());
}

#[test]
fn concatenated_gzip_members_are_composed_deterministically_without_host_extraction() {
    let bytes = [
        tar_gzip("x", tar::EntryType::Regular, b"first"),
        tar_gzip("y", tar::EntryType::Regular, b"second"),
    ]
    .concat();
    let mut results = Vec::new();
    for _ in 0..2 {
        let mut image = archive::Image::new();
        image.tar(&bytes, false, &|| Ok(())).unwrap();
        let (home, _) = fixture();
        let store = store::Store::open(&home, KEY, true).unwrap();
        let (_, expanded) = image.finish(&store, &spec(), &|| Ok(())).unwrap();
        assert!(expanded >= 11);
        let compressed = store.read("ramdisk.cpio.gz", 1_048_576).unwrap();
        let mut unpacked = Vec::new();
        flate2::read::MultiGzDecoder::new(compressed.as_slice())
            .read_to_end(&mut unpacked)
            .unwrap();
        assert!(unpacked.windows(5).any(|w| w == b"first"));
        assert!(unpacked.windows(6).any(|w| w == b"second"));
        let mut offset = 0;
        let mut inputs = 0;
        loop {
            assert_eq!(&unpacked[offset..offset + 6], b"070701");
            let field = |n: usize| {
                usize::from_str_radix(
                    std::str::from_utf8(&unpacked[offset + 6 + n * 8..offset + 14 + n * 8])
                        .unwrap(),
                    16,
                )
                .unwrap()
            };
            let mode = field(1);
            let size = field(6);
            let length = field(11);
            let name =
                std::str::from_utf8(&unpacked[offset + 110..offset + 110 + length - 1]).unwrap();
            if name == "TRAILER!!!" {
                break;
            }
            if ["x", "y"].contains(&name) {
                assert_eq!(mode, 0o100755);
                inputs += 1;
            }
            offset = (offset + 110 + length + 3) & !3;
            offset = (offset + size + 3) & !3;
        }
        assert_eq!(inputs, 2);
        results.push(compressed);
    }
    assert_eq!(results[0], results[1]);
}

#[test]
fn zip_paths_and_kernel_header_ranges_are_validated_before_publication() {
    use zip::{write::SimpleFileOptions, ZipWriter};
    let mut zip = ZipWriter::new(io::Cursor::new(Vec::new()));
    zip.start_file("../escape", SimpleFileOptions::default())
        .unwrap();
    zip.write_all(b"data").unwrap();
    assert_eq!(
        archive::Image::new().zip(zip.finish().unwrap().into_inner(), &|| Ok(())),
        Err("unsupported_input")
    );
    assert_eq!(archive::kernel(b"short"), Err("unsupported_input"));
    let mut kernel = vec![0; 64];
    kernel[4..8].copy_from_slice(b"zimg");
    kernel[8..12].copy_from_slice(&u32::MAX.to_le_bytes());
    kernel[12..16].copy_from_slice(&100u32.to_le_bytes());
    kernel[24..29].copy_from_slice(b"gzip\0");
    assert_eq!(archive::kernel(&kernel), Err("unsupported_input"));
}
