#!/usr/bin/env python3
"""Finite Codex contract fixture; never contacts a provider."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

signal.alarm(20)
args = sys.argv[1:]
assert "--ephemeral" in args and "--ignore-user-config" in args
assert args[args.index("--ask-for-approval") + 1] == "never"
prompt = sys.stdin.read()
data = json.loads(prompt.split("BOSS delivery input (JSON):\n", 1)[1])
mode = os.environ.get("BOSS_DELIVERY_MODE", "approved")
root = Path(os.environ["BOSS_DELIVERY_FIXTURE"])
schema = Path(args[args.index("--output-schema") + 1]) if "--output-schema" in args else None
kind = "plan" if schema and schema.name == "plan_schema.json" else "review" if schema else "implement"
cycle = data.get("cycle", 0)
with (root / "calls").open("a") as calls:
    calls.write(json.dumps({"kind": kind, "cycle": cycle, "cwd": str(Path.cwd()), "target_commit": data.get("target_commit")}) + "\n")

def emit(value):
    print(json.dumps(value), flush=True)

emit({"type": "turn.started"})
emit({"type": "item.completed", "item": {"type": "agent_message", "text": "RAW_MODEL_SECRET_SENTINEL"}})
print("RAW_AGENT_STDERR_SECRET_SENTINEL", file=sys.stderr, flush=True)

if mode == "wait" and kind == "implement":
    (root / "waiting").write_text(str(os.getpid()))
    while True:
        time.sleep(0.1)

if kind == "implement":
    assert args[args.index("--sandbox") + 1] == "workspace-write"
    assert data["plan"]["acceptance"] == ["Create result.txt"]
    if cycle > 1:
        assert Path("first-only.txt").read_text() == "retained first attempt\n"
        assert data["previous_feedback"]["kind"] in ("checks", "review")
        check = data["previous_feedback"]["check_receipt"]
        assert check["output_complete"] is True and len(check["output_hash"]) == 64
        assert check["stdout_bytes"] > 0 and check["stderr_bytes"] > 0
    Path("first-only.txt").write_text("retained first attempt\n")
    contents = "unchanged" if mode in ("repeated", "check_repeated") else f"candidate-{cycle}"
    Path("result.txt").write_text(contents + "\n")
else:
    assert args[args.index("--sandbox") + 1] == "read-only"
    output = Path(args[args.index("--output-last-message") + 1])
    if kind == "plan":
        report = {"summary": "Create the result", "steps": ["Write result.txt"], "acceptance": ["Create result.txt"], "file_scopes": None}
        scope_file = root / "scopes.json"
        if scope_file.exists():
            predictions = json.loads(scope_file.read_text())
            selected = [value for name, value in predictions.items() if f"# {name}\n" in data["specification"]]
            assert len(selected) == 1
            report["file_scopes"] = selected[0]
        if mode == "plan_dirty":
            Path("result.txt").write_text("planner changed tracked file")
        if mode == "plan_invalid":
            report["acceptance"] = []
    else:
        assert data["plan"]["acceptance"] == ["Create result.txt"]
        assert "CHECK_STDOUT_SECRET_SENTINEL" in data["check_output"]["stdout"]
        assert "CHECK_STDERR_SECRET_SENTINEL" in data["check_output"]["stderr"]
        assert data["check_receipt"]["output_complete"] is True
        assert data["check_receipt"]["exit_code"] == 0
        assert "first-only.txt" in data["diff"] and "result.txt" in data["diff"]
        if "target_commit" in data:
            expected = subprocess.check_output(["git", "diff", "--no-ext-diff", "--no-textconv", "--binary", "--full-index", data["target_commit"], data["candidate_commit"], "--"], text=True).rstrip("\n")
            assert data["target_diff"] == expected
            assert data["original_review"]["verdict"] == "approved"
            assert len(data["original_candidate"]) in (40, 64)
            assert "fresh integration review" in prompt
            if mode == "integration_wait":
                (root / "integration-review-wait").write_text(str(os.getpid()))
                while not (root / "integration-review-release").exists():
                    time.sleep(0.05)
        first = Path("result.txt").read_text() == "candidate-1\n"
        reject = mode in ("reject_always", "repeated") or (mode == "reject_once" and first)
        unclear = mode == "needs_spec"
        criterion = "Another criterion" if mode == "coverage" else "Create result.txt"
        report = {
            "verdict": "needs_spec_revision" if unclear else "changes_requested" if reject else "approved",
            "summary": "Needs changes" if reject or unclear else "Matches the saved requirements",
            "acceptance": [{"criterion": criterion, "status": "unclear" if unclear else "failed" if reject else "passed", "evidence": "result.txt was inspected"}],
            "issues": [{"criterion": criterion, "message": "Clarify expected output" if unclear else "Correct result.txt contents"}] if reject or unclear else []
        }
        if mode == "repeated" and data["previous_feedback"]:
            report["issues"][0]["message"] = "  Correct  result.txt contents  "
    output.write_text(json.dumps(report))

emit({"type": "turn.completed", "usage": {"input_tokens": 3, "output_tokens": 2}})
