use super::*;

pub(super) fn request() -> Value {
    json!({"contract":CONTRACT,"key":"00000000-0000-4000-8000-000000000001",
        "deadline_unix_ms":now().unwrap()+60000,"image":{},"input":{},"check":{
        "request_id":"00000000-0000-4000-8000-000000000002","check_id":"00000000-0000-4000-8000-000000000003",
        "input_key":"00000000-0000-4000-8000-000000000004","candidate_sha":"a".repeat(40),"manifest_sha256":"b".repeat(64),
        "image_spec_sha256":"c".repeat(64),"toolchain":"npm","directory":".","arguments":["test","--offline"],"timeout_seconds":20}})
}

#[test]
fn vm_scope_and_budget_refuse_unknown_tools_paths_and_extra_authority() {
    assert!(time_valid(Some(99), 90, 100));
    for time in [None, Some(89), Some(100), Some(101)] {
        assert!(!time_valid(time, 90, 100));
    }
    let input = request();
    assert!(validate(&input).is_ok());
    for (field, value) in [
        ("contract", json!("foreign")),
        ("key", json!("../bad")),
        ("deadline_unix_ms", json!(true)),
        ("deadline_unix_ms", json!(now().unwrap() - 1)),
        ("deadline_unix_ms", json!(now().unwrap() + 400000)),
    ] {
        let mut changed = input.clone();
        changed[field] = value;
        assert!(validate(&changed).is_err());
    }
    for (field, value) in [
        ("toolchain", json!("sh")),
        ("directory", json!("../escape")),
        ("timeout_seconds", json!(0)),
        ("arguments", json!(["test\n--unsafe"])),
        ("candidate_sha", json!("B".repeat(40))),
    ] {
        let mut changed = input.clone();
        changed["check"][field] = value;
        assert!(validate(&changed).is_err());
    }
    let mut changed = input;
    changed["helper"] = json!("/bin/sh");
    assert!(validate(&changed).is_err());
}

#[test]
fn guest_configuration_contains_only_closed_root_owned_request_paths() {
    let bytes = config_archive(b"{\"bound\":true}");
    assert!(bytes.starts_with(b"070701"));
    assert!(bytes.windows(19).any(|s| s == b"requests/check.json"));
    assert!(!bytes.windows(4).any(|s| s == b".git"));
    assert!(bytes.windows(14).any(|s| s == b"{\"bound\":true}"));
}

#[test]
fn preflight_refusal_reserves_a_single_use_scope_and_replay_cannot_prove_cleanup() {
    let (root, _, mut args) = super::super::tests::fixture();
    let home = root.parent().unwrap().join("runtime-home");
    fs::create_dir(&home).unwrap();
    fs::set_permissions(&home, fs::Permissions::from_mode(0o700)).unwrap();
    args[0] = "run_guest_check".into();
    args[4] = home.to_str().unwrap().into();
    args.push(request().to_string());
    assert_eq!(
        super::super::operation_limit(&args),
        Duration::from_secs(360)
    );
    let (_tx, rx) = mpsc::channel();
    let first = super::super::run(&args, rx, Duration::from_secs(60)).unwrap();
    assert_eq!(first["native_started"], false);
    assert_eq!(first["cleanup_verified"], true);
    let receipt = fs::read(
        home.join("check-runs")
            .join(request()["key"].as_str().unwrap())
            .join("receipt.json"),
    )
    .unwrap();
    let (_tx, rx) = mpsc::channel();
    let replay = super::super::run(&args, rx, Duration::from_secs(60)).unwrap();
    assert_eq!(replay["status"], "image_exists");
    assert_eq!(replay["cleanup_verified"], false);
    assert_eq!(
        fs::read(
            home.join("check-runs")
                .join(request()["key"].as_str().unwrap())
                .join("receipt.json")
        )
        .unwrap(),
        receipt
    );
}

#[test]
fn vm_closure_is_exact_retained_scope_not_process_absence_or_worker_success() {
    let (root, _, _) = super::super::tests::fixture();
    let home = root.parent().unwrap().join("runtime-home");
    fs::create_dir(&home).unwrap();
    fs::set_permissions(&home, fs::Permissions::from_mode(0o700)).unwrap();
    let request = request();
    let key = request["key"].as_str().unwrap();
    let store = Store::run(&home, key).unwrap();
    let intent = json!({"key":key,"check":request["check"]});
    let expected = json!({"contract":CONTRACT,"key":key,"request_id":request["check"]["request_id"],
        "check_id":request["check"]["check_id"],"input_key":request["check"]["input_key"],"candidate_sha":request["check"]["candidate_sha"],
        "intent_sha256":"d".repeat(64),"native_state":0,"vm_closed":true,"status":"passed","source_unchanged":true,
        "stdout_bytes":3,"observed_stdout_bytes":3,"stdout_sha256":"e".repeat(64),"exit_code":0});
    store
        .write("closure.json", expected.to_string().as_bytes())
        .unwrap();
    assert_eq!(
        closure(
            &store,
            expected.to_string().as_bytes(),
            &intent,
            &"d".repeat(64)
        )
        .unwrap(),
        expected
    );
    assert!(closure(&store, b"{}", &intent, &"d".repeat(64)).is_err());
    for (field, value) in [
        ("native_state", json!(true)),
        ("native_state", json!(1)),
        ("vm_closed", json!(false)),
        ("key", json!("foreign")),
        ("contract", json!("guest-check-v1")),
        ("exit_code", json!(true)),
        ("source_unchanged", json!(false)),
        ("stdout_bytes", json!(65537)),
        ("cleanup_verified", json!(true)),
    ] {
        let mut changed = expected.clone();
        changed[field] = value;
        fs::write(
            home.join("check-runs").join(key).join("closure.json"),
            changed.to_string(),
        )
        .unwrap();
        assert!(
            closure(
                &store,
                changed.to_string().as_bytes(),
                &intent,
                &"d".repeat(64)
            )
            .is_err(),
            "{field}"
        );
    }
    let mut changed = expected;
    changed.as_object_mut().unwrap().remove("stdout_bytes");
    fs::write(
        home.join("check-runs").join(key).join("closure.json"),
        changed.to_string(),
    )
    .unwrap();
    assert!(closure(
        &store,
        changed.to_string().as_bytes(),
        &intent,
        &"d".repeat(64)
    )
    .is_err());
}

#[test]
fn literal_check_binding_is_length_framed_and_matches_the_host() {
    let check = json!({"request_id":"a", "check_id":"b", "input_key":"c", "candidate_sha":"d",
      "manifest_sha256":"e", "image_spec_sha256":"f", "toolchain":"npm", "directory":"sub/路径",
      "arguments":["test", "a b", "quote\"", "slash/"], "timeout_seconds":30});
    assert_eq!(
        binding(&check),
        "11feff7b81335be7e814162c5812827bfdd56d341eda2de195ae92031ab66f55"
    );
    let mut changed = check.clone();
    changed["arguments"][0] = json!("different");
    assert_ne!(binding(&changed), binding(&check));
}

#[test]
fn failure_excerpt_is_opt_in_bounded_utf8_and_never_applies_to_uncertain_results() {
    let mut input = request();
    input["feedback"] = json!(FEEDBACK);
    assert!(validate(&input).is_ok());
    input["feedback"] = json!("arbitrary-log-access");
    assert!(validate(&input).is_err());
    let mut row = json!({"status":"failed","cleanup_verified":true});
    let mut enabled = request();
    enabled["feedback"] = json!(FEEDBACK);
    attach_feedback(
        &mut row,
        &enabled,
        Some(b"\x1b[31mexpected yes\x1b[0m\n\x00\xff"),
    );
    assert_eq!(row["failure_output"]["excerpt"], "expected yes\n\u{fffd}");
    assert_eq!(
        row["failure_output"]["excerpt_sha256"],
        initial::digest("expected yes\n\u{fffd}".as_bytes())
    );
    let long = "\u{1f600}".repeat(2000);
    attach_feedback(&mut row, &enabled, Some(long.as_bytes()));
    assert_eq!(row["failure_output"]["excerpt_bytes"], 4096);
    assert_eq!(row["failure_output"]["truncated"], true);
    for status in [
        "passed",
        "cancelled",
        "timeout",
        "invalid_output",
        "cleanup_uncertain",
    ] {
        let mut refused = json!({"status":status,"cleanup_verified":true});
        attach_feedback(&mut refused, &enabled, Some(b"never project this"));
        assert!(refused.get("failure_output").is_none());
    }
    for (req, clean) in [(request(), true), (enabled, false)] {
        let mut refused = json!({"status":"failed","cleanup_verified":clean});
        attach_feedback(&mut refused, &req, Some(b"never project this"));
        assert!(refused.get("failure_output").is_none());
    }
}
