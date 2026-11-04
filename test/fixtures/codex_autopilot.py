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
if args[-2:] == ["debug", "models"]:
    assert args == ["--config", 'model_provider="openai"', "debug", "models"]
    print(json.dumps({"models": [
        {"slug": name, "visibility": "list",
         "supported_reasoning_levels": [{"effort": value} for value in ["medium", "high", "xhigh"]]}
        for name in ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]
    ]}))
    sys.exit(0)
prompt = sys.stdin.read()
schema = Path(args[args.index("--output-schema") + 1]) if "--output-schema" in args else None
if schema and schema.name == "intake_schema.json":
    assert args[args.index("--sandbox") + 1] == "read-only"
    intake = json.loads(prompt.split("BOSS project intake input (JSON):\n", 1)[1])
    assert "Already implemented: existing.txt" in intake["documents"]["docs/product.md"]
    assert "result.txt" in intake["documents"]["docs/architecture.md"]
    assert Path("existing.txt").read_text() == "implemented"
    assert Path("result.txt").read_text() == "base"
    calls = Path(os.environ["BOSS_DELIVERY_FIXTURE"]) / "calls"
    previous = [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []
    attempt = 1 + sum(call["kind"] == "intake" for call in previous)
    with calls.open("a") as log:
        log.write(json.dumps({"kind": "intake", "attempt": attempt,
                             "model": args[args.index("--model") + 1] if "--model" in args else None}) + "\n")
    print(json.dumps({"type": "turn.started"}), flush=True)
    report = {"tasks": [
        {"id": name, "title": name, "specification": "Write the requested output.",
         "acceptance": ["Create result.txt"], "depends_on": deps,
         "sources": ["docs/product.md"]}
        for name, deps in [("two", ["one"]), ("one", [])]
    ]}
    if os.environ.get("BOSS_AUTOPILOT_MODE") == "invalid_intake":
        report["tasks"][0]["depends_on"] = ["missing"]
    mode = os.environ.get("BOSS_AUTOPILOT_MODE")
    if mode == "intake_exhausted" or mode == "intake_repair" and attempt == 1:
        report["tasks"] = [
            {"id": f"oversized_{number}", "title": "A bounded individual task",
             "specification": "x" * 3900, "acceptance": ["Create result.txt"],
             "depends_on": [], "sources": ["docs/product.md"]}
            for number in range(9)
        ]
    Path(args[args.index("--output-last-message") + 1]).write_text(json.dumps(report))
    print(json.dumps({"type": "turn.completed", "usage": {"input_tokens": 1, "output_tokens": 1}}), flush=True)
    sys.exit(0)
data = json.loads(prompt.split("BOSS delivery input (JSON):\n", 1)[1])
assert data["check_config"]["argv"] == ["python3", "check.py"]
schema = Path(args[args.index("--output-schema") + 1]) if "--output-schema" in args else None
kind = "resolve" if schema and schema.name == "resolution_schema.json" else "plan" if schema and schema.name == "plan_schema.json" else "review" if schema else "implement"
name = next(name for name in ("one", "two", "three") if f"# {name}\n" in data["specification"])
root = Path(os.environ["BOSS_DELIVERY_FIXTURE"])
mode = os.environ.get("BOSS_AUTOPILOT_MODE", "approved")
with (root / "calls").open("a") as log:
    log.write(json.dumps({"kind": kind, "task": name, "cwd": str(Path.cwd()),
                         "model": args[args.index("--model") + 1] if "--model" in args else None,
                         "reasoning_effort": next((arg.split("=", 1)[1].strip('"') for arg in args if arg.startswith("model_reasoning_effort=")), None),
                         "resolution_attempt": data.get("resolution_attempt")}) + "\n")
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
    if kind == "resolve":
        report = {"summary": "Use the saved output requirement", "steps": ["Write result.txt as specified"],
                  "assumptions": ["Preserve the existing text format"], "external_action": None}
    elif kind == "plan":
        report = {"summary": "Write result", "steps": ["Write result.txt"],
                  "acceptance": [] if mode == "invalid_first" and name == "one" else ["Create result.txt"], "file_scopes": None}
        if mode == "autonomy_plan" and name == "one" and not data.get("resolution"):
            report["clarification"] = "Which existing output format should be used?"
    else:
        assert data["check_receipt"]["exit_code"] == 0
        assert "result.txt" in data["diff"]
        reject = mode == "repair" and name == "one" and not data["previous_feedback"]
        report = {"verdict": "changes_requested" if reject else "approved", "summary": "Checked result",
                  "acceptance": [{"criterion": "Create result.txt", "status": "failed" if reject else "passed", "evidence": "Inspected result.txt"}],
                  "issues": [{"criterion": "Create result.txt", "message": "Correct result.txt"}] if reject else []}
    Path(args[args.index("--output-last-message") + 1]).write_text(json.dumps(report))
print(json.dumps({"type": "turn.completed", "usage": {"input_tokens": 1, "output_tokens": 1}}), flush=True)
