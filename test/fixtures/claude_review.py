#!/usr/bin/env python3
"""Finite no-tool Claude reviewer fixture; never contacts a provider."""
import json
import os
from pathlib import Path
import signal
import sys
import time

signal.alarm(20)
args = sys.argv[1:]
for flag in ("--print", "--verbose", "--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence"):
    assert flag in args
for key, value in (("--input-format", "text"), ("--output-format", "stream-json"), ("--tools", ""),
                   ("--permission-mode", "dontAsk"), ("--setting-sources", ""), ("--disallowedTools", "mcp__*")):
    assert args[args.index(key) + 1] == value
assert json.loads(args[args.index("--settings") + 1]) == {"disableAllHooks": True, "autoMemoryEnabled": False}
assert json.loads(args[args.index("--mcp-config") + 1]) == {"mcpServers": {}}
assert json.loads(args[args.index("--json-schema") + 1])["required"] == ["verdict", "summary", "acceptance", "issues"]
assert "--bare" not in args and not any("bypass" in arg for arg in args)
assert Path.cwd().name.startswith("boss-claude-review-")
assert not Path("result.txt").exists()
prompt = sys.stdin.read()
assert "No repository, shell, web" in prompt
assert "mark it unclear" in prompt
input = json.loads(prompt.split("BOSS delivery input (JSON):\n", 1)[1])
assert input["reviewer"] == "claude"
assert input["plan"]["acceptance"] == ["Create result.txt"]
assert "CHECK_STDOUT_SECRET_SENTINEL" in input["check_output"]["stdout"]
assert "CHECK_STDERR_SECRET_SENTINEL" in input["check_output"]["stderr"]
assert input["check_receipt"]["output_complete"] is True
assert input["check_receipt"]["exit_code"] == 0
assert "first-only.txt" in input["diff"] and "result.txt" in input["diff"]
root = Path(os.environ["BOSS_DELIVERY_FIXTURE"])
mode = os.environ.get("BOSS_CLAUDE_MODE", "approved")
with (root / "calls").open("a") as calls:
    calls.write(json.dumps({"kind": "claude_review", "cwd": str(Path.cwd())}) + "\n")

def emit(value):
    print(json.dumps(value), flush=True)

emit({"type": "system", "subtype": "init", "tools": ["Read"] if mode == "unsafe_init" else ["StructuredOutput"],
      "mcp_servers": [], "plugins": [], "permissionMode": "dontAsk"})
print("CLAUDE_STDERR_SECRET_SENTINEL", file=sys.stderr, flush=True)
if mode == "wait":
    (root / "claude-waiting").write_text(str(os.getpid()))
    while True:
        time.sleep(0.1)
if mode == "malformed":
    print("not json", flush=True)
    sys.exit(0)
if mode == "oversized":
    print("x" * 262145, flush=True)
    sys.exit(0)
if mode == "external_tool":
    emit({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "external", "name": "Bash", "input": {}}]}})
    sys.exit(0)

rejected = mode == "reject_once" and input["previous_feedback"] is None
unclear = mode == "needs_spec"
criterion = "Incorrect criterion" if mode == "coverage" else "Create result.txt"
report = {
    "verdict": "changes_requested" if rejected else "needs_spec_revision" if unclear else "approved",
    "summary": "Needs changes" if rejected or unclear else "Matches the saved evidence",
    "acceptance": [{"criterion": criterion, "status": "failed" if rejected else "unclear" if unclear else "passed",
                    "evidence": "Complete supplied diff and check output"}],
    "issues": [{"criterion": criterion, "message": "Correct result.txt contents" if rejected else "Clarify expected output"}] if rejected or unclear else []
}
emit({"type": "assistant", "message": {"content": [
    {"type": "text", "text": "CLAUDE_MODEL_SECRET_SENTINEL"},
    {"type": "tool_use", "id": "structured1", "name": "StructuredOutput", "input": report}
]}})
emit({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "structured1", "content": "Success"}]}})
result = {"type": "result", "subtype": "error_max_turns" if mode == "error" else "success",
          "is_error": mode == "error", "permission_denials": [{"tool_name": "Bash"}] if mode == "denied" else [],
          "structured_output": report, "usage": {"input_tokens": 12, "output_tokens": 4},
          "result": "CLAUDE_RESULT_SECRET_SENTINEL"}
if mode == "missing_report":
    del result["structured_output"]
if mode == "truncated":
    print(json.dumps(result), end="", flush=True)
else:
    emit(result)
if mode == "duplicate":
    emit(result)
sys.exit(7 if mode == "nonzero" else 0)
