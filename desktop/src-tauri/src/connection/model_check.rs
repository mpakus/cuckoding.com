//! One fixed diagnostic turn, never repository work or a general RPC bridge.
use super::*;

const PROFILE: &str = "cuckoding-model-check";
const ACK: &str = "CC_READY";
const PROMPT: &str =
    "Reply with exactly CC_READY. Do not use tools, read files, or perform any other action.";
const DISABLED: &[&str] = &[
    "shell_tool",
    "unified_exec",
    "apply_patch_freeform",
    "apps",
    "plugins",
    "js_repl",
    "code_mode",
    "code_mode_host",
    "computer_use",
    "browser_use",
    "in_app_browser",
    "image_generation",
    "multi_agent",
    "multi_agent_v2",
    "memories",
    "memory_tool",
    "hooks",
    "codex_hooks",
    "plugin_hooks",
    "external_agent_memory_import",
    "request_permissions",
    "request_permissions_tool",
    "shell_snapshot",
    "skill_mcp_dependency_install",
    "skill_env_var_dependency_prompt",
];

fn permissions(scratch: &Path) -> Value {
    json!({"filesystem": {":root":"deny", scratch.to_str().unwrap():"read"},
        "network":{"enabled":false}})
}

pub(super) fn configure(command: &mut Command, scratch: &Path) -> Result<()> {
    private_directory(scratch).map_err(|_| "unsafe_profile")?;
    if std::fs::read_dir(scratch)
        .map_err(|_| "unsafe_profile")?
        .next()
        .is_some()
    {
        return Err("unsafe_profile");
    }
    command.args([
        "-c",
        "default_permissions=\"cuckoding-model-check\"",
        "-c",
        "project_doc_max_bytes=0",
        "-c",
        "web_search=\"disabled\"",
        "-c",
        "developer_instructions=\"\"",
    ]);
    let profile = format!(
        "permissions.{PROFILE}={{filesystem={{\":root\"=\"deny\",{}=\"read\"}},network={{enabled=false}}}}",
        serde_json::to_string(scratch.to_str().ok_or("unsafe_profile")?).unwrap()
    );
    command.args(["-c", &profile]);
    for feature in DISABLED {
        command.args(["-c", &format!("features.{feature}=false")]);
    }
    Ok(())
}

fn validate_config(config: &Value, scratch: &Path) -> Result<()> {
    if config["default_permissions"] != PROFILE
        || without_nulls(config["permissions"][PROFILE].clone()) != permissions(scratch)
        || !config["sandbox_mode"].is_null()
        || config["approval_policy"] != "never"
        || config["web_search"] != "disabled"
        || config["project_doc_max_bytes"] != 0
        || !config["model_instructions_file"].is_null()
        || !(config["mcp_servers"].is_null() || config["mcp_servers"] == json!({}))
        || DISABLED
            .iter()
            .any(|feature| config["features"][feature] != false)
    {
        return Err("unsupported_grant");
    }
    Ok(())
}

// config/read expands omitted optional fields to null in Codex 0.146.0.
fn without_nulls(value: Value) -> Value {
    match value {
        Value::Object(map) => Value::Object(
            map.into_iter()
                .filter(|(_, v)| !v.is_null())
                .map(|(k, v)| (k, without_nulls(v)))
                .collect(),
        ),
        other => other,
    }
}

pub(super) fn check(
    rpc: &mut Rpc,
    config: &Value,
    scratch: &Path,
    model: &str,
    effort: &str,
) -> Result<Value> {
    identifier(&json!(model)).map_err(|_| "invalid_output")?;
    identifier(&json!(effort)).map_err(|_| "invalid_output")?;
    validate_config(config, scratch)?;
    if account(rpc)?["account"]["type"] != "chatgpt" {
        return Err("not_connected");
    }
    let available = catalog(rpc)?;
    if !available.iter().any(|row| {
        row["model"] == model
            && row["efforts"]
                .as_array()
                .is_some_and(|e| e.contains(&json!(effort)))
    }) {
        return Err("model_unavailable");
    }
    let thread = rpc.request("thread/start", json!({
        "model":model, "modelProvider":"openai", "cwd":scratch,
        "approvalPolicy":"never", "permissions":PROFILE, "ephemeral":true,
        "allowProviderModelFallback":false, "experimentalRawEvents":false,
        "environments":[], "dynamicTools":[], "runtimeWorkspaceRoots":[scratch],
        "baseInstructions":"You perform one connection diagnostic. Follow the fixed prompt without tools.",
        "developerInstructions":"No tools or file access. Return only the requested acknowledgement.",
        "config":{"model_reasoning_effort":effort}
    }))?;
    validate_thread(&thread, scratch, model, effort)?;
    let thread_id = identifier(&thread["thread"]["id"])
        .map_err(|_| "invalid_output")?
        .to_owned();
    rpc.capture = true;
    let start = rpc.request(
        "turn/start",
        json!({"threadId":thread_id,
        "input":[{"type":"text","text":PROMPT}], "model":model, "effort":effort}),
    )?;
    let turn_id = identifier(&start["turn"]["id"])
        .map_err(|_| "invalid_output")?
        .to_owned();
    let result = completion(rpc, &thread_id, &turn_id);
    if result.is_err() {
        rpc.capture = false;
        rpc.deadline = Instant::now() + Duration::from_secs(1);
        rpc.wall_deadline = SystemTime::now() + Duration::from_secs(1);
        let _ = rpc.request(
            "turn/interrupt",
            json!({"threadId":thread_id,"turnId":turn_id}),
        );
    }
    result?;
    Ok(
        json!({"status":"passed", "requested_model":model, "observed_model":thread["model"],
        "effort":effort, "thread_id":thread_id, "turn_id":turn_id, "grant":"scratch-read-only-v1"}),
    )
}

fn validate_thread(thread: &Value, scratch: &Path, model: &str, effort: &str) -> Result<()> {
    if thread["model"] != model {
        return Err("model_mismatch");
    }
    if thread["modelProvider"] != "openai"
        || thread["cwd"].as_str() != scratch.to_str()
        || thread["approvalPolicy"] != "never"
        || thread["reasoningEffort"] != effort
        || thread["activePermissionProfile"]["id"] != PROFILE
        || !thread["activePermissionProfile"]["extends"].is_null()
        || thread["sandbox"]["type"] != "readOnly"
        || thread["sandbox"]["networkAccess"] != false
        || thread["instructionSources"] != json!([])
        // 0.146.0 returns no workspace roots for an exact-path read-only profile.
        || !(thread["runtimeWorkspaceRoots"] == json!([])
            || thread["runtimeWorkspaceRoots"] == json!([scratch]))
        || thread["thread"]["ephemeral"] != true
        || !thread["thread"]["path"].is_null()
        || thread["thread"]["cwd"].as_str() != scratch.to_str()
    {
        return Err("unsupported_grant");
    }
    Ok(())
}

fn completed_item(item: &Value, final_id: &mut Option<String>) -> Result<()> {
    match item["type"].as_str() {
        Some("userMessage" | "reasoning") => Ok(()),
        Some("agentMessage") => {
            if item["phase"] == "commentary" {
                return Ok(());
            }
            if item["text"].as_str().map(str::trim) != Some(ACK) {
                return Err("invalid_response");
            }
            let id = identifier(&item["id"]).map_err(|_| "invalid_output")?;
            if final_id.as_ref().is_some_and(|known| known != id) {
                return Err("invalid_response");
            }
            *final_id = Some(id.to_owned());
            Ok(())
        }
        _ => Err("unexpected_tool"),
    }
}

fn completion(rpc: &mut Rpc, thread: &str, turn: &str) -> Result<()> {
    let mut final_id = None;
    loop {
        let message = match rpc.pending.pop_front() {
            Some(event) => event,
            None => rpc.next()?,
        };
        let method = message["method"].as_str().ok_or("unexpected_message")?;
        let params = &message["params"];
        if params.get("threadId").is_some_and(|id| id != thread)
            || params.get("turnId").is_some_and(|id| id != turn)
        {
            return Err("unexpected_message");
        }
        match method {
            "turn/started" | "turn/completed" => {
                if params["threadId"] != thread || params["turn"]["id"] != turn {
                    return Err("unexpected_message");
                }
                if method == "turn/completed" {
                    if params["turn"]["status"] != "completed" || !params["turn"]["error"].is_null()
                    {
                        return Err("turn_failed");
                    }
                    for item in params["turn"]["items"].as_array().ok_or("invalid_output")? {
                        completed_item(item, &mut final_id)?;
                    }
                    return if final_id.is_some() {
                        Ok(())
                    } else {
                        Err("invalid_response")
                    };
                }
            }
            "item/started" | "item/completed" => {
                if params["threadId"] != thread || params["turnId"] != turn {
                    return Err("unexpected_message");
                }
                if !matches!(
                    params["item"]["type"].as_str(),
                    Some("userMessage" | "reasoning" | "agentMessage")
                ) {
                    return Err("unexpected_tool");
                }
                if method == "item/completed" {
                    completed_item(&params["item"], &mut final_id)?;
                }
            }
            "model/rerouted" => return Err("model_mismatch"),
            "error" => return Err("turn_failed"),
            "thread/status/changed"
            | "thread/tokenUsage/updated"
            | "thread/started"
            | "account/rateLimits/updated"
            | "serverRequest/resolved" => {}
            _ if method.starts_with("item/reasoning") || method == "item/agentMessage/delta" => {}
            _ => return Err("unexpected_message"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::connection::tests::{fixture, sample};
    use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf};
    const THREAD: &str = "019ce111-1111-7111-8111-111111111111";
    const TURN: &str = "019ce222-2222-7222-8222-222222222222";

    fn model_fixture(mode: &str) -> (PathBuf, PathBuf, PathBuf) {
        let (dir, path) = fixture(Value::Null, json!([]));
        let scratch = dir.join("scratch");
        fs::create_dir(&scratch).unwrap();
        fs::set_permissions(&scratch, fs::Permissions::from_mode(0o700)).unwrap();
        let mut config = json!({"cli_auth_credentials_store":"file", "model_provider":"openai",
            "default_permissions":PROFILE, "permissions":{PROFILE:permissions(&scratch)},
            "approval_policy":"never", "web_search":"disabled", "project_doc_max_bytes":0});
        for feature in DISABLED {
            config["features"][feature] = json!(false);
        }
        // Real config/read includes explicit null defaults; these grant nothing.
        config["permissions"][PROFILE]["extends"] = Value::Null;
        config["permissions"][PROFILE]["filesystem"]["glob_scan_max_depth"] = Value::Null;
        if mode == "unsafe" {
            config["permissions"][PROFILE]["filesystem"][":root"] = json!("read");
        }
        let config = json!({"config":config});
        let init = json!({"codexHome":dir});
        let mut entry = sample();
        entry["model"] = json!("test-model");
        let model = "test-model";
        // Use the actual model-list wire shape, not our normalized metadata.
        entry["supportedReasoningEfforts"] = json!([{"reasoningEffort":"low"}]);
        entry["defaultReasoningEffort"] = json!("low");
        let models = json!({"data":[entry],"nextCursor":null});
        let mut started = json!({"model":model,"modelProvider":"openai","cwd":scratch,
            "approvalPolicy":"never","reasoningEffort":"low", "activePermissionProfile":{"id":PROFILE,"extends":null},
            "sandbox":{"type":"readOnly","networkAccess":false},"instructionSources":[],"runtimeWorkspaceRoots":[],
            "thread":{"id":THREAD,"cwd":scratch,"ephemeral":true,"path":null}});
        if mode == "model" {
            started["model"] = json!("different-model");
        }
        if mode == "grant" {
            started["sandbox"]["networkAccess"] = json!(true);
        }
        if mode == "roots" {
            started["runtimeWorkspaceRoots"] = json!(["/Users"]);
        }
        let item = if mode == "tool" {
            json!({"type":"commandExecution","id":"tool","command":"fixture-secret"})
        } else {
            json!({"type":"agentMessage","id":"answer","phase":"final_answer","text":if mode=="text" {"fixture-secret"} else {ACK}})
        };
        let completed = json!({"method":"turn/completed","params":{"threadId":if mode=="foreign" {"foreign"} else {THREAD},
            "turn":{"id":TURN,"status":"completed","items":[item],"error":null}}});
        fs::write(&path, format!(r#"#!/bin/sh
while IFS= read -r line; do
 id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
 case "$line" in
  *'"method":"initialize"'*) result='{init}' ;;
  *'"method":"initialized"'*) continue ;;
  *'"method":"config/read"'*) result='{config}' ;;
  *'"method":"account/read"'*) result='{{"account":{{"type":"chatgpt","email":"fixture-secret"}},"requiresOpenaiAuth":true}}' ;;
  *'"method":"model/list"'*) result='{models}' ;;
  *'"method":"thread/start"'*) result='{started}'; printf '%s' "$line" > "$CODEX_HOME/thread-request" ;;
  *'"method":"turn/start"'*)
   echo started > "$CODEX_HOME/turn-started"
   if test '{mode}' != wait; then printf '%s\n' '{completed}'; fi
   result='{{"turn":{{"id":"{TURN}","status":"inProgress","items":[]}}}}' ;;
  *'"method":"turn/interrupt"'*) echo interrupted > "$CODEX_HOME/interrupted"; result='{{}}' ;;
  *) exit 9 ;;
 esac
 printf '{{"id":%s,"result":%s}}\n' "$id" "$result"
done
"#)).unwrap();
        (dir, path, scratch)
    }

    #[test]
    fn model_check_binds_early_completion_and_keeps_only_public_receipt() {
        let (dir, path, scratch) = model_fixture("success");
        let (_sender, cancel) = mpsc::channel();
        let result = run_operation(
            &path,
            &dir,
            cancel,
            Duration::from_secs(2),
            Operation::Check {
                scratch: &scratch,
                model: "test-model",
                effort: "low",
            },
            |_| panic!("no auth link expected"),
        )
        .unwrap();
        assert_eq!(result["status"], "passed");
        assert_eq!(result["thread_id"], THREAD);
        assert_eq!(result["turn_id"], TURN);
        assert_eq!(result["observed_model"], "test-model");
        assert!(!result.to_string().contains("fixture-secret"));
        let request: Value =
            serde_json::from_slice(&fs::read(dir.join("thread-request")).unwrap()).unwrap();
        assert_eq!(request["params"]["permissions"], PROFILE);
        assert_eq!(request["params"]["ephemeral"], true);
        assert_eq!(request["params"]["environments"], json!([]));
        assert_eq!(request["params"]["allowProviderModelFallback"], false);
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn model_check_refuses_grant_model_tool_foreign_and_invalid_answer() {
        for (mode, status, launched) in [
            ("unsafe", "unsupported_grant", false),
            ("grant", "unsupported_grant", false),
            ("roots", "unsupported_grant", false),
            ("model", "model_mismatch", false),
            ("tool", "unexpected_tool", true),
            ("foreign", "unexpected_message", true),
            ("text", "invalid_response", true),
            ("wait", "timeout", true),
        ] {
            let (dir, path, scratch) = model_fixture(mode);
            let (_sender, cancel) = mpsc::channel();
            let result = run_operation(
                &path,
                &dir,
                cancel,
                Duration::from_millis(400),
                Operation::Check {
                    scratch: &scratch,
                    model: "test-model",
                    effort: "low",
                },
                |_| Ok(()),
            )
            .unwrap();
            assert_eq!(result["status"], status, "{mode}");
            assert_eq!(dir.join("turn-started").exists(), launched);
            assert_eq!(dir.join("interrupted").exists(), launched);
            assert!(!result.to_string().contains("fixture-secret"));
            assert!(profile_lock(&dir).is_ok());
            fs::remove_dir_all(dir).unwrap();
        }
    }

    #[test]
    fn model_check_cancellation_interrupts_and_releases_profile() {
        let (dir, path, scratch) = model_fixture("wait");
        let (sender, cancel) = mpsc::channel();
        let marker = dir.join("turn-started");
        let signal = thread::spawn(move || {
            for _ in 0..100 {
                if marker.exists() {
                    thread::sleep(Duration::from_millis(40));
                    sender.send(()).unwrap();
                    return;
                }
                thread::sleep(Duration::from_millis(10));
            }
            panic!("fixture did not start");
        });
        let result = run_operation(
            &path,
            &dir,
            cancel,
            Duration::from_secs(2),
            Operation::Check {
                scratch: &scratch,
                model: "test-model",
                effort: "low",
            },
            |_| Ok(()),
        )
        .unwrap();
        signal.join().unwrap();
        assert_eq!(result["status"], "cancelled");
        assert!(dir.join("interrupted").exists());
        assert!(profile_lock(&dir).is_ok());
        fs::remove_dir_all(dir).unwrap();
    }
}
