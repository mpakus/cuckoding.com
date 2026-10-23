use super::*;
const KEY: &str = "00000000-0000-4000-8000-000000000171";

#[test]
fn retained_capture_requires_exact_complete_proof_without_replaying_effects() {
    let (root, home, request, original) = inspection_fixture();
    let args = &request[..5];
    let battle = initial(
        args,
        "create_battle",
        json!({"key":BATTLE_KEY,"head":original["head"]}),
    )
    .unwrap();
    let prepared = initial(args, "battle_worktree", json!({"key":KEY,"battle":battle})).unwrap();
    let mut preparation = prepared.clone();
    preparation.as_object_mut().unwrap().remove("status");
    let checkout = Path::new(prepared["path"].as_str().unwrap());
    fs::write(checkout.join("docs/plan.txt"), "candidate\n").unwrap();
    let files = json!([{"path":"docs/plan.txt","sha256":initial::digest(b"candidate\n")}]);
    let capture = json!({"key":CANDIDATE_KEY,"preparation":preparation,"files":files});
    let receipt = initial(args, "capture_candidate", capture.clone()).unwrap();
    let recovery =
        json!({"key":CANDIDATE_KEY,"battle":battle,"preparation":preparation,"files":files});
    let index = fs::read(root.join(".git/index")).unwrap();
    let source = fs::read(root.join("docs/plan.txt")).unwrap();
    assert_eq!(
        initial(args, "recover_battle_candidate", recovery.clone()).unwrap(),
        receipt
    );
    assert_eq!(
        initial(args, "recover_battle_candidate", recovery.clone()).unwrap(),
        receipt
    );
    assert_eq!(
        initial(args, "capture_candidate", capture),
        Err("candidate_exists")
    );
    let directory = home.join(format!("worktrees/{KEY}/candidate-{CANDIDATE_KEY}"));
    for name in ["intent.json", "publication.json", "receipt.json"] {
        let path = directory.join(name);
        let bytes = fs::read(&path).unwrap();
        fs::remove_file(&path).unwrap();
        assert!(
            initial(args, "recover_battle_candidate", recovery.clone()).is_err(),
            "missing {name}"
        );
        assert!(!path.exists(), "missing proof was reconstructed");
        fs::write(&path, "{}").unwrap();
        assert!(
            initial(args, "recover_battle_candidate", recovery.clone()).is_err(),
            "tampered {name}"
        );
        fs::write(&path, bytes).unwrap();
        let saved = directory.join(format!("saved-{name}"));
        fs::rename(&path, &saved).unwrap();
        std::os::unix::fs::symlink(&saved, &path).unwrap();
        assert!(
            initial(args, "recover_battle_candidate", recovery.clone()).is_err(),
            "linked {name}"
        );
        fs::remove_file(&path).unwrap();
        fs::rename(saved, &path).unwrap();
    }
    let mut foreign = recovery.clone();
    foreign["files"][0]["sha256"] = json!("a".repeat(64));
    assert!(initial(args, "recover_battle_candidate", foreign).is_err());
    let mut extra = recovery.clone();
    extra["extra"] = json!(true);
    assert!(initial(args, "recover_battle_candidate", extra).is_err());
    let tag = home.join(format!("worktrees/{KEY}/battle.json"));
    let bytes = fs::read(&tag).unwrap();
    fs::write(&tag, "{}").unwrap();
    assert!(initial(args, "recover_battle_candidate", recovery.clone()).is_err());
    fs::write(&tag, bytes).unwrap();
    fs::write(checkout.join("docs/plan.txt"), "drift").unwrap();
    assert!(initial(args, "recover_battle_candidate", recovery.clone()).is_err());
    fs::write(checkout.join("docs/plan.txt"), "candidate\n").unwrap();
    let mut native_args = args.to_vec();
    native_args[0] = "recover_battle_candidate".into();
    native_args.push(recovery.to_string());
    assert_eq!(operation_limit(&native_args), Duration::from_secs(60));
    let (tx, rx) = mpsc::channel();
    tx.send(()).unwrap();
    assert_eq!(
        run(&native_args, rx, Duration::from_secs(15)),
        Err("cancelled")
    );
    let (_, rx) = mpsc::channel();
    assert_eq!(run(&native_args, rx, Duration::ZERO), Err("timeout"));
    assert_eq!(
        initial(args, "recover_battle_candidate", recovery).unwrap(),
        receipt
    );
    assert_eq!(fs::read(root.join(".git/index")).unwrap(), index);
    assert_eq!(fs::read(root.join("docs/plan.txt")).unwrap(), source);
    assert_eq!(
        fs::read(checkout.join("docs/plan.txt")).unwrap(),
        b"candidate\n"
    );
    fs::remove_dir_all(root.parent().unwrap()).unwrap();
}
