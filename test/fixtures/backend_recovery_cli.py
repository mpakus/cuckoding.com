#!/usr/bin/env python3
"""Finite provider/check fixture for abrupt backend death; never calls a provider."""
import json
import os
from pathlib import Path
import signal
import sys
import time

signal.alarm(60)
root = Path(os.environ["BOSS_BACKEND_RECOVERY_ROOT"])
boundary = os.environ["BOSS_BACKEND_RECOVERY_BOUNDARY"]


def checkpoint():
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    child = os.fork()
    if child == 0:
        signal.alarm(60)
        while True:
            time.sleep(0.05)
    marker = root / "processes.tmp"
    marker.write_text(json.dumps({"leader": os.getpid(), "child": child,
                                 "guardian": os.getppid(), "cwd": str(Path.cwd())}))
    marker.rename(root / "processes.json")
    while True:
        time.sleep(0.05)


if Path(sys.argv[0]).name == "check.py":
    assert Path("result.txt").read_text() == "candidate-1\n"
    calls = root / "check-calls"
    with calls.open("a") as output:
        output.write(str(Path.cwd()) + "\n")
    if boundary == "post_check" and len(calls.read_text().splitlines()) == 2:
        checkpoint()
    sys.exit(0)

args = sys.argv[1:]
assert "--ephemeral" in args and "--ignore-user-config" in args
assert args[args.index("--ask-for-approval") + 1] == "never"
assert args[-1] == "-"
data = json.loads(sys.stdin.read().split("BOSS delivery input (JSON):\n", 1)[1])
assert data["check_config"]["argv"] == ["python3", "check.py"]
schema = Path(args[args.index("--output-schema") + 1]) if "--output-schema" in args else None
kind = "plan" if schema and schema.name == "plan_schema.json" else "review" if schema else "implement"
with (root / "calls").open("a") as output:
    output.write(kind + "\n")
print(json.dumps({"type": "turn.started"}), flush=True)
if kind == "implement":
    assert args[args.index("--sandbox") + 1] == "workspace-write"
    Path("result.txt").write_text("candidate-1\n")
    if boundary == "implement":
        checkpoint()
else:
    assert args[args.index("--sandbox") + 1] == "read-only"
    if kind == "plan":
        report = {"summary": "Write result", "steps": ["Write result.txt"],
                  "acceptance": ["Create result.txt"], "file_scopes": None}
    else:
        assert data["check_receipt"]["exit_code"] == 0
        assert "result.txt" in data["diff"]
        report = {"verdict": "approved", "summary": "Checked result",
                  "acceptance": [{"criterion": "Create result.txt", "status": "passed",
                                  "evidence": "Inspected result.txt"}], "issues": []}
    Path(args[args.index("--output-last-message") + 1]).write_text(json.dumps(report))
print(json.dumps({"type": "turn.completed", "usage": {"input_tokens": 1, "output_tokens": 1}}), flush=True)
