use super::*;
use crate::arena_git::tests::{commit_fixture, fixture, git as command, operation};
use std::{
    collections::BTreeMap,
    os::unix::fs::{symlink, PermissionsExt},
};

const KEY: &str = "00000000-0000-4000-8000-000000000152";
const OTHER: &str = "00000000-0000-4000-8000-000000000153";

fn setup() -> (std::path::PathBuf, std::path::PathBuf, Vec<String>, Value) {
    let (root, home, args) = fixture();
    operation(&args, "init").unwrap();
    fs::create_dir(root.join("src")).unwrap();
    fs::write(root.join("src/binary file"), [0, 255, 13, 10]).unwrap();
    fs::write(root.join("test.sh"), "#!/bin/sh\nexit 0\n").unwrap();
    fs::set_permissions(root.join("test.sh"), fs::Permissions::from_mode(0o755)).unwrap();
    fs::write(
        root.join("AGENTS.md"),
        "Untrusted project text, not a native command.",
    )
    .unwrap();
    commit_fixture(&root, &home);
    let head = operation(&args, "inspect").unwrap()["head"].clone();
    let prepared = call(
        &args,
        "worktree",
        json!({"key":"00000000-0000-4000-8000-000000000151", "head":head}),
    )
    .unwrap();
    (root, home, args, prepared)
}

fn call(args: &[String], op: &str, request: Value) -> Result<Value> {
    let mut args = args.to_vec();
    args.push(request.to_string());
    operation(&args, op)
}

fn prepare(args: &[String], preparation: &Value) -> Value {
    call(
        args,
        "prepare_check_input",
        json!({"key":KEY,"preparation":preparation}),
    )
    .unwrap()
}

fn verify(args: &[String], preparation: &Value, input: &Value) -> Result<Value> {
    call(
        args,
        "verify_check_input",
        json!({"key":KEY,"preparation":preparation,"input":input}),
    )
}

fn unpack(bytes: &[u8]) -> BTreeMap<String, (u32, u32, Vec<u8>)> {
    let mut offset = 0;
    let mut files = BTreeMap::new();
    loop {
        assert_eq!(&bytes[offset..offset + 6], b"070701");
        let fields: Vec<_> = bytes[offset + 6..offset + 110]
            .chunks_exact(8)
            .map(|part| u32::from_str_radix(std::str::from_utf8(part).unwrap(), 16).unwrap())
            .collect();
        assert_eq!(
            (fields[3], fields[5], fields[7], fields[8], fields[9], fields[10], fields[12]),
            (fields[2], 0, 0, 0, 0, 0, 0)
        );
        let end = offset + 110 + fields[11] as usize;
        assert_eq!(bytes[end - 1], 0);
        let name = std::str::from_utf8(&bytes[offset + 110..end - 1]).unwrap();
        let start = (end + 3) & !3;
        offset = (start + fields[6] as usize + 3) & !3;
        if name == "TRAILER!!!" {
            assert_eq!(offset, bytes.len());
            break;
        }
        assert!(files
            .insert(
                name.into(),
                (
                    fields[1],
                    fields[2],
                    bytes[start..start + fields[6] as usize].to_vec()
                )
            )
            .is_none());
    }
    files
}

#[test]
fn check_input_transports_exact_commit_with_closed_modes_and_no_git_or_user_edits() {
    let (root, home, args, prepared) = setup();
    let index = fs::read(root.join(".git/index")).unwrap();
    let head = fs::read(root.join(".git/refs/heads/main")).unwrap();
    fs::write(root.join("src/binary file"), "UNCOMMITTED_CANARY").unwrap();
    let result = prepare(&args, &prepared);
    assert_eq!(result["status"], "check_input_prepared");
    assert_eq!(result["candidate_sha"], prepared["head"]);
    assert_eq!(result["file_count"], 3);
    let path = home.join("check-inputs").join(KEY);
    let bytes = fs::read(path.join("candidate.cpio")).unwrap();
    assert_eq!(result["archive_sha256"], initial::digest(&bytes));
    assert_eq!(result["archive_bytes"], bytes.len());
    let files = unpack(&bytes);
    assert_eq!(
        files["work/checkout/src/binary file"],
        (0o100644, 1000, vec![0, 255, 13, 10])
    );
    assert_eq!(files["work/checkout/test.sh"].0, 0o100755);
    assert_eq!(files["work/checkout/test.sh"].1, 1000);
    assert_eq!(files["requests/candidate.json"].0, 0o100444);
    assert_eq!(files["requests/candidate.json"].1, 0);
    assert_eq!(
        files["requests/candidate.json"].2,
        fs::read(path.join("manifest.json")).unwrap()
    );
    assert!(!files
        .keys()
        .any(|name| name.contains(".git") || name.starts_with('/')));
    let listed = Command::new("/usr/bin/tar")
        .args(["-tf", path.join("candidate.cpio").to_str().unwrap()])
        .env_clear()
        .output()
        .unwrap();
    assert!(listed.status.success());
    assert!(String::from_utf8(listed.stdout)
        .unwrap()
        .contains("work/checkout/test.sh"));
    assert_eq!(
        verify(&args, &prepared, &result).unwrap()["status"],
        "check_input_verified"
    );
    assert_eq!(
        call(
            &args,
            "prepare_check_input",
            json!({"key":KEY,"preparation":prepared})
        ),
        Err("check_input_exists")
    );
    assert_eq!(fs::read(root.join(".git/index")).unwrap(), index);
    assert_eq!(fs::read(root.join(".git/refs/heads/main")).unwrap(), head);
    assert_eq!(
        fs::read(root.join("src/binary file")).unwrap(),
        b"UNCOMMITTED_CANARY"
    );
    for name in [
        "intent.json",
        "receipt.json",
        "manifest.json",
        "candidate.cpio",
    ] {
        assert_eq!(fs::metadata(path.join(name)).unwrap().mode() & 0o777, 0o600);
    }
}

#[test]
fn check_input_verification_refuses_tampering_forged_receipts_and_partial_linked_artifacts() {
    let (_, home, args, prepared) = setup();
    let result = prepare(&args, &prepared);
    let path = home.join("check-inputs").join(KEY);
    for name in [
        "intent.json",
        "receipt.json",
        "manifest.json",
        "candidate.cpio",
    ] {
        let file = path.join(name);
        let original = fs::read(&file).unwrap();
        fs::write(&file, b"tampered").unwrap();
        assert!(verify(&args, &prepared, &result).is_err(), "{name}");
        assert_eq!(fs::read(&file).unwrap(), b"tampered");
        fs::write(&file, &original).unwrap();
    }
    let archive = path.join("candidate.cpio");
    let original = fs::read(&archive).unwrap();
    fs::write(&archive, b"forged archive").unwrap();
    let mut forged = result.clone();
    forged["archive_sha256"] = json!(initial::digest(b"forged archive"));
    forged["archive_bytes"] = json!(14);
    fs::write(path.join("receipt.json"), forged.to_string()).unwrap();
    assert_eq!(
        verify(&args, &prepared, &forged),
        Err("check_input_mismatch")
    );
    fs::write(&archive, &original).unwrap();
    fs::write(path.join("receipt.json"), result.to_string()).unwrap();
    fs::hard_link(&archive, path.join("alias")).unwrap();
    assert_eq!(
        verify(&args, &prepared, &result),
        Err("check_input_mismatch")
    );
    fs::remove_file(path.join("alias")).unwrap();
    fs::remove_file(&archive).unwrap();
    symlink(path.join("manifest.json"), &archive).unwrap();
    assert_eq!(
        verify(&args, &prepared, &result),
        Err("check_input_mismatch")
    );
    fs::remove_file(&archive).unwrap();
    fs::write(&archive, &original).unwrap();
    fs::set_permissions(&archive, fs::Permissions::from_mode(0o600)).unwrap();
    fs::set_permissions(
        path.join("manifest.json"),
        fs::Permissions::from_mode(0o644),
    )
    .unwrap();
    assert_eq!(
        verify(&args, &prepared, &result),
        Err("check_input_mismatch")
    );
    fs::set_permissions(
        path.join("manifest.json"),
        fs::Permissions::from_mode(0o600),
    )
    .unwrap();
    let receipt = fs::read(path.join("receipt.json")).unwrap();
    fs::remove_file(path.join("receipt.json")).unwrap();
    assert!(verify(&args, &prepared, &result).is_err());
    assert!(!path.join("receipt.json").exists());
    fs::write(path.join("receipt.json"), receipt).unwrap();
    fs::set_permissions(path.join("receipt.json"), fs::Permissions::from_mode(0o600)).unwrap();
    assert!(verify(&args, &prepared, &result).is_ok());
}

#[test]
fn check_input_refuses_foreign_changed_or_extra_checkout_and_storage_aliases_before_publication() {
    let (_, home, args, prepared) = setup();
    let checkout = Path::new(prepared["path"].as_str().unwrap());
    let request = |preparation: &Value| {
        call(
            &args,
            "prepare_check_input",
            json!({"key":OTHER,"preparation":preparation}),
        )
    };
    let mut foreign = prepared.clone();
    foreign["head"] = json!("a".repeat(40));
    assert_eq!(request(&foreign), Err("check_input_mismatch"));
    let file = checkout.join("src/binary file");
    command(
        checkout,
        &home,
        &["update-index", "--assume-unchanged", "src/binary file"],
    );
    fs::write(&file, b"changed").unwrap();
    assert_eq!(request(&prepared), Err("check_input_mismatch"));
    fs::remove_file(&file).unwrap();
    symlink(checkout.join("test.sh"), &file).unwrap();
    assert_eq!(request(&prepared), Err("check_input_mismatch"));
    fs::remove_file(&file).unwrap();
    fs::hard_link(checkout.join("test.sh"), &file).unwrap();
    assert_eq!(request(&prepared), Err("check_input_mismatch"));
    fs::remove_file(&file).unwrap();
    fs::write(&file, [0, 255, 13, 10]).unwrap();
    fs::write(checkout.join("extra"), "untracked").unwrap();
    assert_eq!(request(&prepared), Err("check_input_mismatch"));
    fs::remove_file(checkout.join("extra")).unwrap();
    assert!(!home.join("check-inputs").exists());
    let outside = home.join("outside");
    fs::create_dir(&outside).unwrap();
    symlink(&outside, home.join("check-inputs")).unwrap();
    assert_eq!(request(&prepared), Err("check_input_mismatch"));
    assert_eq!(fs::read_dir(&outside).unwrap().count(), 0);
}

#[test]
fn check_input_preserves_limits_layout_refusal_and_cancelled_admission() {
    for paths in [vec!["A/one", "a/two"], vec!["x", "x/child"]] {
        assert_eq!(portable_paths(paths.into_iter()), Err("unsafe_tree"));
    }
    let mut archive = Archive {
        file: io::sink(),
        digest: Sha256::new(),
        bytes: ARCHIVE_LIMIT,
        inode: 0,
    };
    assert_eq!(archive.write(b"x"), Err("tree_limit"));
    archive.bytes = 0;
    archive.inode = 20_000;
    assert_eq!(archive.entry("x", 0o100644, 1000, b""), Err("tree_limit"));
    let (_, home, mut args, prepared) = setup();
    args[0] = "prepare_check_input".into();
    args.push(json!({"key":KEY,"preparation":prepared}).to_string());
    let (tx, rx) = mpsc::channel();
    tx.send(()).unwrap();
    assert_eq!(
        crate::arena_git::run(&args, rx, Duration::from_secs(60)),
        Err("cancelled")
    );
    let (_tx, rx) = mpsc::channel();
    assert_eq!(
        crate::arena_git::run(&args, rx, Duration::ZERO),
        Err("timeout")
    );
    assert!(!home.join("check-inputs").exists());
}

#[test]
fn check_input_empty_committed_tree_has_only_fixed_guest_directories_and_manifest() {
    let (root, home, args) = fixture();
    operation(&args, "init").unwrap();
    commit_fixture(&root, &home);
    let head = operation(&args, "inspect").unwrap()["head"].clone();
    let prepared = call(&args, "worktree", json!({"key":OTHER,"head":head})).unwrap();
    let result = prepare(&args, &prepared);
    assert_eq!(result["file_count"], 0);
    assert_eq!(result["content_bytes"], 0);
    let files =
        unpack(&fs::read(home.join("check-inputs").join(KEY).join("candidate.cpio")).unwrap());
    assert_eq!(
        files.keys().map(String::as_str).collect::<Vec<_>>(),
        [
            "requests",
            "requests/candidate.json",
            "work",
            "work/checkout"
        ]
    );
    assert_eq!(
        verify(&args, &prepared, &result).unwrap()["status"],
        "check_input_verified"
    );
}
