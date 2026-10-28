#!/usr/bin/env python3
"""Finite local provider fixture for sequential task publication and review repair."""
import json
import os
from pathlib import Path
import signal
import sys
import time

signal.alarm(60)
args = sys.argv[1:]
data = json.loads(sys.stdin.read().split("BOSS delivery input (JSON):\n", 1)[1])
assert data["check_config"]["argv"] == ["python3", "check.py"]
schema = Path(args[args.index("--output-schema") + 1]) if "--output-schema" in args else None
kind = "plan" if schema and schema.name == "plan_schema.json" else "review" if schema else "implement"
name = "two" if "# two\n" in data["specification"] else "one"
root = Path(os.environ["BOSS_DELIVERY_FIXTURE"])
mode = os.environ.get("BOSS_AUTOPILOT_MODE", "approved")
with (root / "calls").open("a") as log:
    log.write(json.dumps({"kind": kind, "task": name, "cwd": str(Path.cwd())}) + "\n")
print(json.dumps({"type": "turn.started"}), flush=True)
if kind == "implement":
    assert args[args.index("--sandbox") + 1] == "workspace-write"
    cycle = data["cycle"]
    gate = Path(os.environ["BOSS_AUTOPILOT_GATES"]) / f"{name}-{cycle}"
    gate.with_suffix(".waiting").write_text(str(os.getpid()))
    while not gate.with_suffix(".release").exists():
        time.sleep(0.02)
    if cycle > 1:
        assert data["previous_feedback"]["kind"] == "review"
    Path("result.txt").write_text(f"{name}-{cycle}\n")
else:
    assert args[args.index("--sandbox") + 1] == "read-only"
    if kind == "plan":
        report = {"summary": "Write result", "steps": ["Write result.txt"],
                  "acceptance": [] if mode == "invalid" else ["Create result.txt"], "file_scopes": None}
    else:
        assert data["check_receipt"]["exit_code"] == 0
        assert "result.txt" in data["diff"]
        reject = mode == "repair" and name == "one" and not data["previous_feedback"]
        report = {"verdict": "changes_requested" if reject else "approved", "summary": "Checked result",
                  "acceptance": [{"criterion": "Create result.txt", "status": "failed" if reject else "passed", "evidence": "Inspected result.txt"}],
                  "issues": [{"criterion": "Create result.txt", "message": "Correct result.txt"}] if reject else []}
    Path(args[args.index("--output-last-message") + 1]).write_text(json.dumps(report))
print(json.dumps({"type": "turn.completed", "usage": {"input_tokens": 1, "output_tokens": 1}}), flush=True)
