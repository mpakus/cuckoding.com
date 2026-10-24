use super::*;
use std::path::PathBuf;

fn query() -> Value {
    let request = super::super::tests::request();
    let mut check = request["check"].clone();
    check.as_object_mut().unwrap().remove("manifest_sha256");
    check.as_object_mut().unwrap().remove("image_spec_sha256");
    json!({"contract":"retained-guest-check-v1","key":request["key"],
        "check":check,"image":{"key":"00000000-0000-4000-8000-000000000005","spec_sha256":"c".repeat(64)}})
}

#[test]
fn retained_check_query_is_closed_and_has_only_exact_original_binding() {
    let original = query();
    assert!(validate_query(&original).is_ok());
    for (field, value) in [
        ("contract", json!("foreign")),
        ("key", json!("../escape")),
        ("check", json!({})),
        ("image", json!(null)),
        ("feedback", json!("unknown")),
        ("path", json!("/private/tmp/arbitrary-log")),
    ] {
        let mut altered = original.clone();
        altered[field] = value;
        assert!(validate_query(&altered).is_err(), "{field}");
    }
    let mut enabled = original;
    enabled["feedback"] = json!(FEEDBACK);
    assert!(validate_query(&enabled).is_ok());
}

struct Fixture {
    store: Store,
    request: Value,
    query: Value,
    source: Value,
    scope: Vec<u8>,
    receipt: Value,
}

impl Fixture {
    fn new(status: &str, feedback: bool) -> Self {
        let (root, _, _) = super::super::super::tests::fixture();
        let home = root.parent().unwrap().join("runtime-home");
        fs::create_dir(&home).unwrap();
        fs::set_permissions(&home, fs::Permissions::from_mode(0o700)).unwrap();
        let mut query = query();
        let mut request = super::super::tests::request();
        request["deadline_unix_ms"] = json!(now().unwrap() - 1);
        request["image"] = json!({"key":query["image"]["key"],"image":query["image"]});
        request["input"] = json!({"key":request["check"]["input_key"],
            "preparation":{"key":request["check"]["input_key"]}});
        if feedback {
            query["feedback"] = json!(FEEDBACK);
            request["feedback"] = json!(FEEDBACK);
        }
        let source = json!({"path":root,"device":1,"inode":2});
        let scope = json!({"source":source,"request":request})
            .to_string()
            .into_bytes();
        let store = Store::run(&home, query["key"].as_str().unwrap()).unwrap();
        for name in ["admission.json", "request.json"] {
            store.write(name, &scope).unwrap();
        }
        store.write("kernel", b"kernel").unwrap();
        store.write("ramdisk.cpio.gz", b"ramdisk").unwrap();
        let mut keeper = store.create("keeper").unwrap();
        keeper.write_all(KEEPER).unwrap();
        keeper
            .set_permissions(fs::Permissions::from_mode(0o700))
            .unwrap();
        keeper.sync_all().unwrap();
        let intent = json!({"contract":CONTRACT,"key":request["key"],"check":request["check"],
            "deadline_unix_ms":request["deadline_unix_ms"],"request_sha256":initial::digest(&scope),
            "kernel_sha256":initial::digest(b"kernel"),"ramdisk_sha256":initial::digest(b"ramdisk"),
            "keeper_sha256":initial::digest(KEEPER)})
        .to_string();
        store.write("intent.json", intent.as_bytes()).unwrap();
        let output = b"expected result\nactual result\n";
        store.write("output.log", output).unwrap();
        let mut receipt = json!({"contract":CONTRACT,"key":request["key"],
            "request_id":request["check"]["request_id"],"check_id":request["check"]["check_id"],
            "input_key":request["check"]["input_key"],"candidate_sha":request["check"]["candidate_sha"],
            "intent_sha256":initial::digest(intent.as_bytes()),"native_state":0,"vm_closed":true,
            "status":status,"source_unchanged":true,"stdout_bytes":output.len(),
            "observed_stdout_bytes":output.len(),"stdout_sha256":initial::digest(output),
            "exit_code":if status=="passed" {0} else {1}});
        for name in ["keeper-stdout", "closure.json"] {
            store.write(name, receipt.to_string().as_bytes()).unwrap();
        }
        receipt["check_sha256"] = json!(binding(&request["check"]));
        receipt["cleanup_verified"] = json!(true);
        attach_feedback(&mut receipt, &request, Some(output));
        store
            .write("receipt.json", receipt.to_string().as_bytes())
            .unwrap();
        Self {
            store,
            request,
            query,
            source,
            scope,
            receipt,
        }
    }

    fn receipt(&self) -> Result<Value> {
        retained_receipt(
            &self.store,
            &self.request,
            &self.scope,
            b"kernel",
            b"ramdisk",
        )
    }

    fn path(&self, name: &str) -> PathBuf {
        PathBuf::from(self.source["path"].as_str().unwrap())
            .parent()
            .unwrap()
            .join("runtime-home/check-runs")
            .join(self.query["key"].as_str().unwrap())
            .join(name)
    }
}

#[test]
fn complete_retained_guest_receipt_is_repeatable_read_only_historical_data() {
    for (status, feedback) in [("passed", false), ("failed", false), ("failed", true)] {
        let f = Fixture::new(status, feedback);
        assert!(validate(&f.request).is_err());
        let (request, bytes) = retained_scope(&f.store, &f.query, &f.source).unwrap();
        assert_eq!(request, f.request);
        assert_eq!(bytes, f.scope);
        let before = fs::read(f.path("receipt.json")).unwrap();
        for _ in 0..2 {
            assert_eq!(f.receipt().unwrap(), f.receipt);
        }
        assert_eq!(before, fs::read(f.path("receipt.json")).unwrap());
        assert_eq!(f.receipt.get("failure_output").is_some(), feedback);
        for (field, changed) in [
            ("key", json!("00000000-0000-4000-8000-000000000099")),
            ("check", json!({})),
            ("image", json!({})),
            ("feedback", json!("unknown")),
        ] {
            let mut query = f.query.clone();
            query[field] = changed;
            assert!(
                retained_scope(&f.store, &query, &f.source).is_err(),
                "{field}"
            );
        }
        assert!(retained_scope(&f.store, &f.query, &json!({"path":"foreign"})).is_err());
    }
}

#[test]
fn keeper_only_or_altered_wrapper_proof_never_establishes_retained_cleanup() {
    for (field, value) in [
        ("cleanup_verified", json!(false)),
        ("cleanup_verified", json!("true")),
        ("status", json!("cancelled")),
        ("check_sha256", json!("f".repeat(64))),
        ("request_id", json!("00000000-0000-4000-8000-000000000099")),
        ("extra", json!("not admitted")),
    ] {
        let f = Fixture::new("passed", false);
        let mut receipt = f.receipt.clone();
        receipt[field] = value;
        fs::write(f.path("receipt.json"), receipt.to_string()).unwrap();
        assert!(f.receipt().is_err(), "{field}");
    }
    for name in [
        "receipt.json",
        "closure.json",
        "keeper-stdout",
        "intent.json",
        "output.log",
    ] {
        let f = Fixture::new("passed", false);
        fs::rename(f.path(name), f.path(&format!("{name}.saved"))).unwrap();
        assert!(f.receipt().is_err(), "{name}");
    }
    let f = Fixture::new("failed", true);
    let mut forged = f.receipt.clone();
    forged["failure_output"]["excerpt"] = json!("different failure");
    fs::write(f.path("receipt.json"), forged.to_string()).unwrap();
    assert!(f.receipt().is_err());
}

#[test]
fn retained_reader_refuses_changed_linked_or_public_native_artifacts() {
    for name in [
        "keeper",
        "kernel",
        "ramdisk.cpio.gz",
        "output.log",
        "request.json",
        "admission.json",
    ] {
        let f = Fixture::new("passed", false);
        fs::write(f.path(name), b"changed").unwrap();
        assert!(f.receipt().is_err(), "{name}");
    }
    for name in ["receipt.json", "output.log", "keeper"] {
        let f = Fixture::new("passed", false);
        fs::hard_link(f.path(name), f.path("second-link")).unwrap();
        assert!(f.receipt().is_err(), "hardlink {name}");
        let f = Fixture::new("passed", false);
        fs::rename(f.path(name), f.path("preserved")).unwrap();
        std::os::unix::fs::symlink(f.path("preserved"), f.path(name)).unwrap();
        assert!(f.receipt().is_err(), "symlink {name}");
        let f = Fixture::new("passed", false);
        fs::set_permissions(f.path(name), fs::Permissions::from_mode(0o644)).unwrap();
        assert!(f.receipt().is_err(), "permissions {name}");
    }
}

#[test]
fn recovery_operation_is_bounded_cancellable_and_never_creates_missing_runs() {
    let (root, _, mut args) = super::super::super::tests::fixture();
    let home = root.parent().unwrap().join("runtime-home");
    fs::create_dir(&home).unwrap();
    fs::set_permissions(&home, fs::Permissions::from_mode(0o700)).unwrap();
    args[0] = "recover_guest_check".into();
    args[4] = home.to_str().unwrap().into();
    args.push(query().to_string());
    assert_eq!(
        super::super::super::operation_limit(&args),
        Duration::from_secs(60)
    );
    let (_tx, rx) = mpsc::channel();
    assert!(super::super::super::run(&args, rx, Duration::from_secs(60)).is_err());
    assert!(!home.join("check-runs").exists());
    let (tx, rx) = mpsc::channel();
    tx.send(()).unwrap();
    assert_eq!(
        super::super::super::run(&args, rx, Duration::from_secs(60)),
        Err("cancelled")
    );
    assert!(!home.join("check-runs").exists());
}
