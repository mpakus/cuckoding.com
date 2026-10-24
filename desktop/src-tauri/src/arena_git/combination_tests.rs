use super::tests::{commit_fixture, fixture, git, operation};
use super::*;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;

fn key(n: usize) -> String {
    format!("00000000-0000-4000-8000-{n:012}")
}

fn initial(args: &[String], operation: &str, request: Value) -> Result<Value> {
    let mut args = args.to_vec();
    args[0] = operation.into();
    args.push(request.to_string());
    let (_sender, cancel) = mpsc::channel();
    run(&args, cancel, operation_limit(&args))
}

struct Fixture {
    root: PathBuf,
    home: PathBuf,
    args: Vec<String>,
    battle: Value,
}

impl Fixture {
    fn new() -> Self {
        let (root, home, args) = fixture();
        operation(&args, "init").unwrap();
        fs::write(root.join("a.txt"), "a base\n").unwrap();
        fs::write(root.join("b.txt"), "b base\n").unwrap();
        fs::write(
            root.join(".gitattributes"),
            "*.txt merge=forbidden-driver\n",
        )
        .unwrap();
        assert_eq!(
            git(
                &root,
                &home,
                &[
                    "config",
                    "merge.forbidden-driver.driver",
                    "touch should-never-run"
                ]
            )
            .0,
            0
        );
        commit_fixture(&root, &home);
        let head = operation(&args, "inspect").unwrap()["head"].clone();
        let battle = initial(&args, "create_battle", json!({"key":key(70),"head":head})).unwrap();
        Self {
            root,
            home,
            args,
            battle,
        }
    }

    fn candidate(&self, n: usize, path: &str, bytes: &str) -> (Value, Value) {
        let mut preparation = initial(
            &self.args,
            "battle_worktree",
            json!({"key":key(n),"battle":self.battle}),
        )
        .unwrap();
        // Phoenix retains the five identity fields, not the native status projection.
        preparation.as_object_mut().unwrap().remove("status");
        let file = Path::new(preparation["path"].as_str().unwrap()).join(path);
        fs::create_dir_all(file.parent().unwrap()).unwrap();
        fs::write(file, bytes).unwrap();
        let candidate = initial(&self.args, "capture_candidate", json!({"key":key(n+10),"preparation":preparation,"files":[{"path":path,"sha256":initial::digest(bytes.as_bytes())}]})).unwrap();
        (preparation, candidate)
    }

    fn integrate(&mut self, preparation: &Value, candidate: &Value, n: usize) {
        self.battle = initial(&self.args, "integrate_candidate", json!({"key":key(n),"battle":self.battle,"preparation":preparation,"candidate":candidate})).unwrap();
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        fs::remove_dir_all(self.root.parent().unwrap()).unwrap();
    }
}

#[test]
fn combination_preserves_independent_results_and_requires_a_new_review_candidate() {
    let mut f = Fixture::new();
    let (first, a) = f.candidate(71, "a.txt", "a result\n");
    let (second, b) = f.candidate(72, "b.txt", "b result\n");
    f.integrate(&first, &a, 91);
    fs::write(f.root.join("a.txt"), "USER_WORKING").unwrap();
    fs::write(f.root.join("untracked.txt"), "USER_UNTRACKED").unwrap();
    let source_index = fs::read(f.root.join(".git/index")).unwrap();
    let head = f.battle["head"].clone();
    let request = json!({"key":key(101),"battle":f.battle,"preparation":second,"candidate":b});
    let combined = initial(&f.args, "combine_candidate", request.clone()).unwrap();
    assert_eq!(combined["status"], "candidate_combined");
    assert_eq!(combined["base"], head);
    assert_eq!(combined["task_base"], b["base"]);
    assert_eq!(combined["task_candidate_key"], b["key"]);
    assert_eq!(
        operation(&f.args, "inspect").unwrap()["head"],
        f.battle["base"]
    );
    assert_eq!(
        initial(&f.args, "combine_candidate", request),
        Err("candidate_exists")
    );
    let review = initial(
        &f.args,
        "battle_worktree",
        json!({"key":key(102),"battle":f.battle,"preparation":second,"candidate":combined}),
    )
    .unwrap();
    let checkout = Path::new(review["path"].as_str().unwrap());
    assert_eq!(fs::read(checkout.join("a.txt")).unwrap(), b"a result\n");
    assert_eq!(fs::read(checkout.join("b.txt")).unwrap(), b"b result\n");
    assert_eq!(
        fs::read(Path::new(second["path"].as_str().unwrap()).join("a.txt")).unwrap(),
        b"a base\n"
    );
    assert_eq!(
        initial(
            &f.args,
            "verify_combined_candidate",
            json!({"battle":f.battle,"preparation":second,"candidate":combined})
        )
        .unwrap()["status"],
        "combined_verified"
    );
    let reviewed = f.battle.clone();
    f.integrate(&second, &combined, 103);
    assert_eq!(f.battle["head"], combined["candidate"]);
    assert_eq!(
        initial(
            &f.args,
            "recover_integration",
            json!({"key":key(103),"battle":reviewed,"preparation":second,"candidate":combined})
        )
        .unwrap(),
        f.battle
    );
    assert_eq!(fs::read(f.root.join("a.txt")).unwrap(), b"USER_WORKING");
    assert_eq!(
        fs::read(f.root.join("untracked.txt")).unwrap(),
        b"USER_UNTRACKED"
    );
    assert_eq!(fs::read(f.root.join(".git/index")).unwrap(), source_index);
    assert!(!f.root.join("should-never-run").exists());
    assert!(!f.home.join("should-never-run").exists());
    assert_eq!(
        initial(
            &f.args,
            "verify_combined_candidate",
            json!({"battle":reviewed,"preparation":second,"candidate":combined})
        ),
        Err("battle_stale")
    );
}

#[test]
fn combination_refuses_overlapping_edits_before_native_effects() {
    let mut f = Fixture::new();
    let (first, a) = f.candidate(71, "a.txt", "first result\n");
    let (second, b) = f.candidate(72, "a.txt", "conflicting result\n");
    f.integrate(&first, &a, 91);
    assert_eq!(
        initial(
            &f.args,
            "combine_candidate",
            json!({"key":key(101),"battle":f.battle,"preparation":second,"candidate":b})
        ),
        Err("candidate_conflict")
    );
    assert!(!f
        .home
        .join("battles")
        .join(key(70))
        .join(format!("combination-{}", key(101)))
        .exists());
    assert_eq!(
        fs::read(Path::new(second["path"].as_str().unwrap()).join("a.txt")).unwrap(),
        b"conflicting result\n"
    );
}

#[test]
fn combination_requires_exact_battle_binding_and_complete_nonreplayable_receipts() {
    let f = Fixture::new();
    let (preparation, candidate) = f.candidate(71, "a.txt", "result\n");
    let foreign = initial(
        &f.args,
        "create_battle",
        json!({"key":key(170),"head":f.battle["base"]}),
    )
    .unwrap();
    assert_eq!(
        initial(
            &f.args,
            "combine_candidate",
            json!({"key":key(101),"battle":foreign,"preparation":preparation,"candidate":candidate})
        ),
        Err("candidate_mismatch")
    );
    let request =
        json!({"key":key(101),"battle":f.battle,"preparation":preparation,"candidate":candidate});
    let combined = initial(&f.args, "combine_candidate", request.clone()).unwrap();
    let mut altered = combined.clone();
    altered["task_base"] = f.battle["head"].clone();
    altered["task_candidate_key"] = json!(key(999));
    assert_eq!(
        initial(
            &f.args,
            "verify_combined_candidate",
            json!({"battle":f.battle,"preparation":preparation,"candidate":altered})
        ),
        Err("candidate_mismatch")
    );
    let directory = f
        .home
        .join("battles")
        .join(key(70))
        .join(format!("combination-{}", key(101)));
    fs::remove_file(directory.join("receipt.json")).unwrap();
    assert_eq!(
        initial(
            &f.args,
            "verify_combined_candidate",
            json!({"battle":f.battle,"preparation":preparation,"candidate":combined})
        ),
        Err("candidate_mismatch")
    );
    assert_eq!(
        initial(&f.args, "combine_candidate", request),
        Err("candidate_exists")
    );
    fs::remove_file(f.home.join("worktrees").join(key(71)).join("battle.json")).unwrap();
    assert_eq!(
        initial(
            &f.args,
            "combine_candidate",
            json!({"key":key(102),"battle":f.battle,"preparation":preparation,"candidate":candidate})
        ),
        Err("candidate_mismatch")
    );
    assert_eq!(
        initial(
            &f.args,
            "verify_candidate",
            json!({"key":candidate["key"],"preparation":preparation,"candidate":candidate})
        )
        .unwrap()["status"],
        "candidate_verified"
    );
}

#[test]
fn combination_budget_applies_only_to_new_operations_and_combined_consumers() {
    for name in ["combine_candidate", "verify_combined_candidate"] {
        assert_eq!(operation_limit(&[name.into()]), Duration::from_secs(60));
    }
    for name in [
        "battle_worktree",
        "integrate_candidate",
        "recover_integration",
    ] {
        let mut args = vec![name.into(), "".into(), "".into(), "".into(), "".into()];
        assert_eq!(operation_limit(&args), Duration::from_secs(15));
        for input in [
            "{".into(),
            " ".repeat(32_769),
            json!({"candidate":{"status":"candidate_captured"}}).to_string(),
        ] {
            args.truncate(5);
            args.push(input);
            assert_eq!(operation_limit(&args), Duration::from_secs(15));
        }
        args.truncate(5);
        args.push(json!({"candidate":{"status":"candidate_combined"}}).to_string());
        assert_eq!(operation_limit(&args), Duration::from_secs(60));
        args[0] = "inspect".into();
        assert_eq!(operation_limit(&args), Duration::from_secs(15));
    }
}

#[test]
fn combination_cancellation_retains_intent_without_advancing_the_battle() {
    let f = Fixture::new();
    let (preparation, candidate) = f.candidate(71, "a.txt", "result\n");
    let mut args = f.args.clone();
    args[0] = "combine_candidate".into();
    args.push(
        json!({"key":key(101),"battle":f.battle,"preparation":preparation,"candidate":candidate})
            .to_string(),
    );
    let directory = f
        .home
        .join("battles")
        .join(key(70))
        .join(format!("combination-{}", key(101)));
    let (sender, receiver) = mpsc::channel();
    let worker = thread::spawn(move || run(&args, receiver, operation_limit(&args)));
    let deadline = Instant::now() + Duration::from_secs(30);
    while !directory.join("intent.json").exists() && Instant::now() < deadline {
        thread::sleep(Duration::from_millis(10));
    }
    let observed = directory.join("intent.json").exists();
    let _ = sender.send(());
    let result = worker.join().unwrap();
    assert!(observed);
    assert_eq!(result, Err("cancelled"));
    assert!(!directory.join("receipt.json").exists());
    assert_eq!(
        initial(&f.args, "verify_battle", json!({"battle":f.battle})).unwrap()["status"],
        "battle_verified"
    );
}

#[test]
fn combined_recovery_reads_exact_complete_proof_without_replaying_or_changing_source() {
    let mut f = Fixture::new();
    let (first, a) = f.candidate(71, "a.txt", "a result\n");
    let (second, b) = f.candidate(72, "b.txt", "b result\n");
    f.integrate(&first, &a, 91);
    let request = json!({"key":key(101),"battle":f.battle,"preparation":second,"candidate":b});
    let combined = initial(&f.args, "combine_candidate", request.clone()).unwrap();
    fs::write(f.root.join("a.txt"), "USER_WORKING").unwrap();
    let index = fs::read(f.root.join(".git/index")).unwrap();
    let directory = f
        .home
        .join("battles")
        .join(key(70))
        .join(format!("combination-{}", key(101)));
    let original: Vec<_> = ["intent.json", "publication.json", "receipt.json", "index"]
        .iter()
        .map(|name| fs::read(directory.join(name)).unwrap())
        .collect();
    for _ in 0..2 {
        assert_eq!(
            initial(&f.args, "recover_combined_candidate", request.clone()).unwrap(),
            combined
        );
        assert_eq!(fs::read(f.root.join(".git/index")).unwrap(), index);
        assert_eq!(fs::read(f.root.join("a.txt")).unwrap(), b"USER_WORKING");
        for (name, bytes) in ["intent.json", "publication.json", "receipt.json", "index"]
            .iter()
            .zip(&original)
        {
            assert_eq!(&fs::read(directory.join(name)).unwrap(), bytes);
        }
    }
    assert_eq!(
        initial(&f.args, "combine_candidate", request),
        Err("candidate_exists")
    );
    assert_eq!(
        initial(&f.args, "verify_battle", json!({"battle":f.battle})).unwrap()["head"],
        f.battle["head"]
    );
    assert_eq!(
        fs::read(Path::new(second["path"].as_str().unwrap()).join("b.txt")).unwrap(),
        b"b result\n"
    );
    assert!(!f.root.join("should-never-run").exists());
}

#[test]
fn combined_recovery_refuses_foreign_partial_linked_changed_and_stale_evidence() {
    let mut f = Fixture::new();
    let (first, a) = f.candidate(71, "a.txt", "a result\n");
    let (second, b) = f.candidate(72, "b.txt", "b result\n");
    f.integrate(&first, &a, 91);
    let request = json!({"key":key(101),"battle":f.battle,"preparation":second,"candidate":b});
    let combined = initial(&f.args, "combine_candidate", request.clone()).unwrap();
    for (field, value) in [
        ("key", json!("../foreign")),
        ("candidate", a),
        ("preparation", first),
        ("extra", json!(true)),
    ] {
        let mut foreign = request.clone();
        foreign[field] = value;
        assert!(initial(&f.args, "recover_combined_candidate", foreign).is_err());
    }
    let directory = f
        .home
        .join("battles")
        .join(key(70))
        .join(format!("combination-{}", key(101)));
    let mut other_request = request.clone();
    other_request["key"] = json!(key(102));
    let other = initial(&f.args, "combine_candidate", other_request).unwrap();
    for name in ["receipt.json", "publication.json"] {
        fs::write(directory.join(name), other.to_string()).unwrap();
    }
    assert_eq!(
        initial(&f.args, "recover_combined_candidate", request.clone()),
        Err("candidate_mismatch")
    );
    for name in ["receipt.json", "publication.json"] {
        fs::write(directory.join(name), combined.to_string()).unwrap();
    }
    for name in ["receipt.json", "publication.json", "intent.json"] {
        let path = directory.join(name);
        let bytes = fs::read(&path).unwrap();
        fs::remove_file(&path).unwrap();
        assert!(initial(&f.args, "recover_combined_candidate", request.clone()).is_err());
        assert!(!path.exists());
        std::os::unix::fs::symlink(directory.join("index"), &path).unwrap();
        assert!(initial(&f.args, "recover_combined_candidate", request.clone()).is_err());
        fs::remove_file(&path).unwrap();
        fs::write(&path, b"{}").unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).unwrap();
        assert!(initial(&f.args, "recover_combined_candidate", request.clone()).is_err());
        fs::write(&path, bytes).unwrap();
    }
    let file = Path::new(second["path"].as_str().unwrap()).join("b.txt");
    fs::write(&file, "changed after capture").unwrap();
    assert!(initial(&f.args, "recover_combined_candidate", request.clone()).is_err());
    fs::write(&file, "b result\n").unwrap();
    assert_eq!(
        initial(&f.args, "recover_combined_candidate", request.clone()).unwrap(),
        combined
    );
    f.integrate(&second, &combined, 103);
    assert_eq!(
        initial(&f.args, "recover_combined_candidate", request),
        Err("battle_stale")
    );
}

#[test]
fn combined_recovery_uses_the_fixed_budget_and_cancellation_without_effects() {
    assert_eq!(
        operation_limit(&["recover_combined_candidate".into()]),
        Duration::from_secs(60)
    );
    let f = Fixture::new();
    let (preparation, candidate) = f.candidate(71, "a.txt", "result\n");
    let request =
        json!({"key":key(101),"battle":f.battle,"preparation":preparation,"candidate":candidate});
    let combined = initial(&f.args, "combine_candidate", request.clone()).unwrap();
    let mut args = f.args.clone();
    args[0] = "recover_combined_candidate".into();
    args.push(request.to_string());
    let (sender, cancel) = mpsc::channel();
    sender.send(()).unwrap();
    assert_eq!(run(&args, cancel, operation_limit(&args)), Err("cancelled"));
    assert_eq!(
        initial(&f.args, "recover_combined_candidate", request).unwrap(),
        combined
    );
}
