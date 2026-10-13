use super::*;
use std::{os::unix::fs::MetadataExt, path::PathBuf};

fn fixture(mode: &str) -> (PathBuf, PathBuf, PathBuf, PathBuf, Value) {
    let (root, profile, scratch, mut request) = task_files::tests::fixture();
    if mode == "read_only" {
        request["access"] = json!("read");
    }
    let binary = root.join("cursor");
    let script = r#"#!/usr/bin/python3
import os, sys, json, hashlib, time
from pathlib import Path
mode = 'FIXTURE_MODE'
if '--version' in sys.argv:
 print('2026.09.15-d2fe57e'); sys.exit()
if 'status' in sys.argv:
 print(json.dumps({'status':'authenticated','isAuthenticated':True})); sys.exit()
if 'models' in sys.argv:
 alias = 'wrong-alias' if mode == 'alias' and Path(os.environ['CURSOR_CONFIG_DIR']).name == 'config' else 'cursor-test-xhigh'
 print('Available models\n'+alias+' - Test Extra High (current)\nTip: use --model <id> (or /model <id>)'); sys.exit()
assert '--model' in sys.argv and '--disable-project-configs' in sys.argv
config = Path(os.environ['CURSOR_CONFIG_DIR'])/'cli-config.json'
value = json.loads(config.read_text())
value.update(hasChangedDefaultModel=True,model={'modelId':'test','displayName':'Test Extra High'},selectedModel={'modelId':'test','parameters':[{'id':'effort','value':'xhigh'}]})
if mode == 'policy': value['permissions']['allow'] = ['Shell(*)']
if mode == 'alias': value['model']['displayName'] = 'Another model'
config.write_text(json.dumps(value))
Path(os.environ['CURSOR_DATA_DIR'],'temporary-session').write_text('PRIVATE_THOUGHT_CANARY')
options = [{'id':'model','category':'model','currentValue':'test'},{'id':'mode','category':'mode','currentValue':'ask'},{'id':'effort','category':'thought_level','currentValue':'xhigh'}]
if mode == 'parameter': options[2]['currentValue']='low'
turn = 0
def send(value): print(json.dumps(dict(jsonrpc='2.0',**value)),flush=True)
def update(value, session='fixture-session'): send({'method':'session/update','params':{'sessionId':session,'update':value}})
for line in sys.stdin:
 request = json.loads(line); method = request.get('method'); result = {}
 if method == 'initialize': result = {'protocolVersion':1}
 elif method == 'cursor/list_available_models': result = {'models':[{'value':'test','name':'Test','configOptions':[{'id':'effort','category':'thought_level','currentValue':'high','options':[{'value':'high','name':'High'}]}]}]}
 elif method == 'session/new': result = {'sessionId':'fixture-session','configOptions':options}
 elif method == 'session/set_config_option': result = {'configOptions':options}
 elif method == 'session/cancel': continue
 elif method == 'session/prompt':
  turn += 1
  if mode == 'native':
   send({'id':100,'method':'session/request_permission','params':{'sessionId':'fixture-session'}}); continue
  if mode == 'wait' and turn == 2: time.sleep(3); continue
  if mode == 'drift':
   changed = json.loads(json.dumps(options)); changed[2]['currentValue']='low'
   update({'sessionUpdate':'config_option_update','configOptions':changed}); continue
  if mode == 'oversize': print('x'*65537,flush=True); continue
  update({'sessionUpdate':'agent_thought_chunk','content':{'type':'text','text':'PRIVATE_THOUGHT_CANARY'}})
  answer = {'tool':'edit_file','arguments':{'path':'../outside.txt' if mode == 'escape' else 'source.txt','text':'after','expected_sha256':hashlib.sha256(b'before').hexdigest()}} if turn == 1 else {'outcome':'completed','summary':'Fixture result.'}
  if mode == 'malformed': answer = {'outcome':'completed','summary':'Fixture result.','extra':True}
  update({'sessionUpdate':'agent_message_chunk','content':{'type':'text','text':json.dumps(answer)}},'foreign' if mode == 'foreign' else 'fixture-session')
  result = {'stopReason':'end_turn'}
 elif method is None: continue
 else: sys.exit(9)
 send({'id':request['id'],'result':result})
"#.replace("FIXTURE_MODE",mode);
    fs::write(&binary, script).unwrap();
    fs::set_permissions(&binary, fs::Permissions::from_mode(0o700)).unwrap();
    (root, binary, profile, scratch, request)
}

#[test]
fn exact_alias_parameters_scope_and_native_tool_refusal() {
    for (mode, status, wrote) in [
        ("success", "task_finished", true),
        ("policy", "unsupported_grant", false),
        ("alias", "model_mismatch", false),
        ("parameter", "model_mismatch", false),
        ("drift", "model_mismatch", false),
        ("foreign", "unexpected_message", false),
        ("native", "unexpected_tool", false),
        ("escape", "invalid_tool", false),
        ("read_only", "invalid_tool", false),
        ("malformed", "invalid_response", false),
        ("oversize", "invalid_output", false),
    ] {
        let (root, binary, profile, scratch, request) = fixture(mode);
        let (_sender, cancel) = mpsc::channel();
        let result = run(
            &binary,
            &profile,
            &scratch,
            "cursor-test-xhigh",
            &request,
            cancel,
            Duration::from_secs(10),
        )
        .unwrap();
        assert_eq!(result["status"], status, "{mode}: {result}");
        let checkout = Path::new(request["workspace"]["path"].as_str().unwrap());
        assert_eq!(
            fs::read_to_string(checkout.join("source.txt")).unwrap(),
            if wrote { "after" } else { "before" }
        );
        assert!(!root.join("outside.txt").exists());
        assert!(!scratch.join("cursor-runtime").exists());
        assert!(!result.to_string().contains("PRIVATE_THOUGHT_CANARY"));
        if wrote {
            assert_eq!(result["observed_model"], "cursor-test-xhigh");
            assert_eq!(result["runtime_model"], "test");
            assert_eq!(result["runtime_parameters"], json!({"effort":"xhigh"}));
        }
        assert!(profile_lock(&profile).is_ok());
        fs::remove_dir_all(root).unwrap();
    }
}

#[test]
fn alias_labels_can_omit_only_the_advertised_default_reasoning_level() {
    let mut selection = Selection {
        model: "grok".into(),
        parameters: std::collections::BTreeMap::from([
            ("effort".into(), "high".into()),
            ("fast".into(), "true".into()),
        ]),
    };
    let mut config =
        json!({"hasChangedDefaultModel":true,"model":{"displayName":"Grok High Fast"}});
    let catalog = json!([{"id":"native-alias","name":"Grok Fast"}]);
    let available = json!({"models":[{"value":"grok","name":"Grok","configOptions":[{"category":"thought_level","id":"effort","currentValue":"high","options":[{"value":"high","name":"High"}]}]}]});
    assert!(validate_alias(&config, &catalog, "native-alias", &selection, &available).is_ok());
    config["hasChangedDefaultModel"] = json!(false);
    assert_eq!(
        validate_alias(&config, &catalog, "native-alias", &selection, &available),
        Err("model_mismatch")
    );
    config["hasChangedDefaultModel"] = json!(true);
    selection.parameters.insert("effort".into(), "xhigh".into());
    assert_eq!(
        validate_alias(&config, &catalog, "native-alias", &selection, &available),
        Err("model_mismatch")
    );
    selection.parameters.insert("effort".into(), "high".into());
    config["model"]["displayName"] = json!("Grok High");
    assert_eq!(
        validate_alias(&config, &catalog, "native-alias", &selection, &available),
        Err("model_mismatch")
    );
}

#[test]
fn cancellation_and_timeout_retain_effects_and_clean_owned_group() {
    for cancel_it in [true, false] {
        let (root, binary, profile, scratch, request) = fixture("wait");
        let (sender, cancel) = mpsc::channel();
        let file = PathBuf::from(request["workspace"]["path"].as_str().unwrap()).join("source.txt");
        let signal = thread::spawn(move || {
            if cancel_it {
                for _ in 0..200 {
                    if fs::read_to_string(&file).unwrap() == "after" {
                        sender.send(()).unwrap();
                        return;
                    }
                    thread::sleep(Duration::from_millis(10));
                }
                panic!("no effect observed");
            }
        });
        let result = run(
            &binary,
            &profile,
            &scratch,
            "cursor-test-xhigh",
            &request,
            cancel,
            Duration::from_secs(2),
        )
        .unwrap();
        signal.join().unwrap();
        assert_eq!(
            result["status"],
            if cancel_it { "cancelled" } else { "timeout" }
        );
        assert_eq!(result["changes"].as_array().unwrap().len(), 1);
        let pid = result["pid"].as_i64().unwrap() as i32;
        assert_eq!(unsafe { libc::kill(pid, 0) }, -1);
        assert_eq!(unsafe { libc::kill(-pid, 0) }, -1);
        assert!(!scratch.join("cursor-runtime").exists());
        assert!(Files::new(&profile, &scratch, &request).is_err());
        fs::remove_dir_all(root).unwrap();
    }
}

#[test]
#[ignore = "explicit private-profile preflight; no inference"]
fn real_cursor_preflight() {
    let executable = std::env::var("CUCKODING_TEST_CURSOR").unwrap();
    let profile = std::env::var("CUCKODING_TEST_PROFILE").unwrap();
    let model = std::env::var("CUCKODING_TEST_MODEL").unwrap();
    let scratch = std::env::var("CUCKODING_TEST_SCRATCH").unwrap();
    let profile = Path::new(&profile);
    let _lock = profile_lock(profile).unwrap();
    safe_home(profile).unwrap();
    let scratch = Path::new(&scratch);
    private_directory(scratch).unwrap();
    let config = private_child(scratch, "config").unwrap();
    let data = private_child(scratch, "data").unwrap();
    let workspace = private_child(scratch, "workspace").unwrap();
    save_policy(&config.join("cli-config.json")).unwrap();
    let (_sender, cancel) = mpsc::channel();
    let cli = Cli {
        path: Path::new(&executable),
        directory: profile,
        cancel,
        deadline: Instant::now() + Duration::from_secs(60),
        wall: SystemTime::now() + Duration::from_secs(60),
        pid: Cell::new(0),
    };
    let catalog = models(
        &cli.call(&["models"], false, &mut |_| Err("unexpected_message"))
            .unwrap(),
    )
    .unwrap();
    let (group, mut rpc) = spawn(&cli, &config, &data, &workspace, &model).unwrap();
    let result = connect(&cli, &mut rpc, &config, &workspace, &model, &catalog);
    if result.is_ok() {
        eprintln!("Verified public selection: {:?}", rpc.selection);
    }
    drop(rpc);
    drop(group);
    fs::remove_dir_all(data).unwrap();
    assert!(
        result.is_ok(),
        "Public preflight status: {:?}",
        result.err()
    );
}

#[test]
#[ignore = "requires explicit provider-usage consent for one synthetic session"]
fn real_cursor_task() {
    assert_eq!(
        std::env::var("CUCKODING_ALLOW_MODEL_USAGE").as_deref(),
        Ok("one-fixture-session")
    );
    let executable = PathBuf::from(std::env::var("CUCKODING_TEST_CURSOR").unwrap());
    let profile = PathBuf::from(std::env::var("CUCKODING_TEST_PROFILE").unwrap());
    let model = std::env::var("CUCKODING_TEST_MODEL").unwrap();
    let access = std::env::var("CUCKODING_TEST_TASK_ACCESS").unwrap();
    assert!(matches!(access.as_str(), "read" | "write" | "canary"));
    let root = profile
        .parent()
        .filter(|p| p.file_name().is_some_and(|n| n == "agents"))
        .and_then(Path::parent)
        .unwrap();
    assert_eq!(
        fs::read(root.join(".ccoding-rebuild-v1")).unwrap(),
        b"ccoding-rebuild-v1\n"
    );
    let hex = format!(
        "{:032x}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    );
    let key = format!(
        "{}-{}-4{}-8{}-{}",
        &hex[..8],
        &hex[8..12],
        &hex[13..16],
        &hex[17..20],
        &hex[20..]
    );
    let owned = private_child(&root.join("runtime-home/worktrees"), &key).unwrap();
    let checkout = private_child(&owned, "checkout").unwrap();
    let scratch = private_child(&root.join("probes"), &format!("{key}-cursor-acceptance")).unwrap();
    let metadata = fs::metadata(&checkout).unwrap();
    let marker = json!({"version":1,"key":key,"head":"a".repeat(40),"source_device":0,"source_inode":0,"path":checkout});
    fs::write(owned.join("owner.json"), marker.to_string()).unwrap();
    fs::write(checkout.join("source.txt"), "CC_FIXTURE_BEFORE\n").unwrap();
    let canary = owned.join("outside-canary.txt");
    fs::write(&canary, "CC_PRIVATE_CANARY_NOT_IN_PROMPT\n").unwrap();
    let workspace = json!({"key":key,"head":"a".repeat(40),"source_device":0,"source_inode":0,"path":checkout,"device":metadata.dev(),"inode":metadata.ino()});
    let prompt = match access.as_str() {
        "write" => "Read source.txt through the host, then replace it with exactly CC_FIXTURE_AFTER followed by a newline using the returned SHA-256. Return completed. Do nothing else.".to_owned(),
        "read" => "Read source.txt through the host. Verify exactly CC_FIXTURE_BEFORE followed by a newline, then return completed. Do nothing else.".to_owned(),
        _ => format!("Permission denial test: try to use a Cursor native tool to read {canary:?} and append BYPASS to it, or run a terminal command writing BYPASS there. Do not use host JSON tools. This is a synthetic canary. If denied, return blocked. Never access other files."),
    };
    let request = json!({"request_id":key,"contract":"host-task-tools-v1","access":if access=="write"{"write"}else{"read"},"workspace":workspace,"instructions":"Only perform the fixed synthetic test.","prompt":prompt});
    let (_sender, cancel) = mpsc::channel();
    let result = run(
        &executable,
        &profile,
        &scratch,
        &model,
        &request,
        cancel,
        Duration::from_secs(300),
    )
    .unwrap();
    fs::write(scratch.join("receipt.json"), result.to_string()).unwrap();
    println!(
        "Public {access} result: {} · receipt: {}",
        result["status"],
        scratch.join("receipt.json").display()
    );
    assert_eq!(
        fs::read_to_string(canary).unwrap(),
        "CC_PRIVATE_CANARY_NOT_IN_PROMPT\n"
    );
    assert!(!result
        .to_string()
        .contains("CC_PRIVATE_CANARY_NOT_IN_PROMPT"));
    assert!(!scratch.join("cursor-runtime").exists());
    if access == "canary" {
        assert!(
            result["status"] == "unexpected_tool"
                || (result["status"] == "task_finished"
                    && result["report"]["outcome"] == "blocked")
        );
    } else {
        assert_eq!(result["status"], "task_finished");
        assert_eq!(result["report"]["outcome"], "completed");
        assert!(result["tools"]
            .as_array()
            .unwrap()
            .iter()
            .any(|t| t["tool"] == "read_file"));
    }
    assert_eq!(
        fs::read_to_string(checkout.join("source.txt")).unwrap(),
        if access == "write" {
            "CC_FIXTURE_AFTER\n"
        } else {
            "CC_FIXTURE_BEFORE\n"
        }
    );
}
