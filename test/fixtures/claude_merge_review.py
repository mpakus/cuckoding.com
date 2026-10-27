#!/usr/bin/env python3
"""Finite evidence-only original/merge reviewer; never contacts a provider."""
import json
import os
from pathlib import Path
import signal
import sys

signal.alarm(20)
args = sys.argv[1:]
for flag in ("--print", "--verbose", "--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence"):
    assert flag in args
for key, value in (("--input-format", "text"), ("--output-format", "stream-json"), ("--tools", ""),
                   ("--permission-mode", "dontAsk"), ("--setting-sources", ""), ("--disallowedTools", "mcp__*")):
    assert args[args.index(key) + 1] == value
assert json.loads(args[args.index("--settings") + 1]) == {"disableAllHooks": True, "autoMemoryEnabled": False}
assert json.loads(args[args.index("--mcp-config") + 1]) == {"mcpServers": {}}
assert Path.cwd().name.startswith("boss-claude-review-")
assert not Path("result.txt").exists()
prompt = sys.stdin.read()
assert "No repository, shell, web" in prompt
assert "mark it unclear" in prompt
data = json.loads(prompt.split("BOSS delivery input (JSON):\n", 1)[1])
assert data["reviewer"] == "claude"
assert data["plan"]["acceptance"] == ["Create result.txt"]
assert "CHECK_STDOUT_SECRET_SENTINEL" in data["check_output"]["stdout"]
assert "CHECK_STDERR_SECRET_SENTINEL" in data["check_output"]["stderr"]
assert data["check_receipt"]["output_complete"] is True
assert data["check_receipt"]["exit_code"] == 0
assert "first-only.txt" in data["diff"] and "result.txt" in data["diff"]
if "target_commit" in data:
    assert "fresh integration review" in prompt
    assert "parallel.txt" in data["diff"]
    assert "parallel.txt" not in data["target_diff"]
    assert "first-only.txt" in data["target_diff"] and "result.txt" in data["target_diff"]
    assert data["original_review"]["verdict"] == "approved"
    assert data["candidate_commit"] not in (data["target_commit"], data["original_candidate"])
root = Path(os.environ["BOSS_DELIVERY_FIXTURE"])
with (root / "calls").open("a") as calls:
    calls.write(json.dumps({"kind": "claude_review", "cwd": str(Path.cwd()),
                           "target_commit": data.get("target_commit"),
                           "candidate_commit": data["candidate_commit"],
                           "original_candidate": data.get("original_candidate")}) + "\n")

def emit(value):
    print(json.dumps(value), flush=True)

report = {"verdict": "approved", "summary": "Complete supplied evidence reviewed",
          "acceptance": [{"criterion": "Create result.txt", "status": "passed",
                          "evidence": "Supplied diff and complete successful check receipt"}], "issues": []}
emit({"type": "system", "subtype": "init", "tools": ["StructuredOutput"],
      "mcp_servers": [], "plugins": [], "permissionMode": "dontAsk"})
print("CLAUDE_STDERR_SECRET_SENTINEL", file=sys.stderr, flush=True)
emit({"type": "assistant", "message": {"content": [
    {"type": "text", "text": "CLAUDE_MODEL_SECRET_SENTINEL"},
    {"type": "tool_use", "id": "structured1", "name": "StructuredOutput", "input": report}
]}})
emit({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "structured1", "content": "Success"}]}})
emit({"type": "result", "subtype": "success", "is_error": False, "permission_denials": [],
      "structured_output": report, "usage": {"input_tokens": 12, "output_tokens": 4},
      "result": "CLAUDE_RESULT_SECRET_SENTINEL"})
