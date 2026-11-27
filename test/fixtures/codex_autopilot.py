#!/usr/bin/env python3
"""Finite local provider fixture for sequential task publication and review repair."""
import hashlib
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
mode = os.environ.get("BOSS_AUTOPILOT_MODE", "approved")
if mode.startswith("greenfield"):
    root = Path(os.environ["BOSS_DELIVERY_FIXTURE"])
    docs_path = "docs/product.md"
    brief = Path(docs_path).read_text()
    if schema and schema.name == "intake_schema.json":
        data = json.loads(prompt.split("BOSS project intake input (JSON):\n", 1)[1])
        assert data["documents"] == {docs_path: brief}
        (root / "brief-base").write_text(data["base_commit"])
        criteria = [line[2:] for line in brief.splitlines() if line.startswith("- ")]
        assert len(criteria) == 3
        if mode in ("greenfield_omission", "greenfield_peer_repair"):
            criteria = criteria[:1]
        task = {"id": "greeting", "title": "Greeting", "specification": "\n".join(criteria),
                "sources": [docs_path], "depends_on": [], "acceptance": criteria}
        report = {"tasks": [] if mode == "greenfield_empty" else [task]}
    else:
        data = json.loads(prompt.split("BOSS delivery input (JSON):\n", 1)[1])
        gate = "Verify the complete project brief" in data["specification"]
        if gate:
            assert brief in data["specification"]
            if mode == "greenfield_peer_repair":
                kind = schema.name if schema else "implement"
                with (root / "peer-calls").open("a") as log:
                    log.write(json.dumps([kind, args[args.index("--model") + 1]]) + "\n")
        if schema and schema.name == "plan_schema.json":
            if gate:
                assert data["brief_documents"] == {docs_path: brief}
                criteria = data["brief_criteria"]
            else:
                spec_criteria = data["specification"].split("## Acceptance criteria\n")[1]
                criteria = [line[2:] for line in spec_criteria.split("## Source documents")[0]
                            .splitlines() if line.startswith("- ")]
            report = {"summary": "Implement the greeting CLI", "steps": ["Check hello.py"],
                      "acceptance": criteria, "file_scopes": None}
        elif schema and schema.name == "resolution_schema.json":
            assert gate and data["previous_feedback"]["report"]["verdict"] == "changes_requested"
            external = None if mode == "greenfield_peer_repair" else "The fixture's replacement implementation is unavailable."
            report = {"summary": "The named greeting and argument limit need repair.",
                      "steps": ["Implement argument handling and rerun checks."], "assumptions": [],
                      "external_action": external}
        elif schema:
            assert data["check_receipt"]["exit_code"] == 0
            source = data["diff"]
            failed = set()
            if gate:
                assert data["brief_base_commit"] == (root / "brief-base").read_text()
                source = data["brief_diff"]
                for criterion in data["plan"]["acceptance"]:
                    line = brief.splitlines()[int(criterion.split(":L")[1]) - 1]
                    if "One name argument" in line and "sys.argv[1]" not in source:
                        failed.add(criterion)
                    if "Extra arguments" in line and "file=sys.stderr" not in source:
                        failed.add(criterion)
            assert "hello.py" in source
            report = {
                "verdict": "changes_requested" if failed else "approved",
                "summary": "Inspected the published-base diff and executable check.",
                "issues": [{"criterion": c, "message": "Argument handling is missing."}
                           for c in sorted(failed)],
                "acceptance": [{"criterion": c, "status": "failed" if c in failed else "passed",
                                "evidence": "Inspected greeting CLI argument handling and check output."}
                               for c in data["plan"]["acceptance"]]
            }
        else:
            repairing = mode == "greenfield_peer_repair" and gate and data["cycle"] == 2
            if repairing:
                feedback = data["previous_feedback"]
                assert {issue["criterion"] for issue in feedback["report"]["issues"]} == {"S1:L6", "S1:L7"}
                assert "Implement argument handling and rerun checks." in feedback["resolution"]["steps"]
                assert Path("hello.py").read_text() == "print('hello')\n"
            if repairing or not Path("hello.py").exists():
                omit = mode in ("greenfield_omission", "greenfield_peer_repair") and not repairing
                script = "print('hello')\n" if omit else """import sys

if len(sys.argv) > 2:
    print("usage: hello.py [name]", file=sys.stderr)
    sys.exit(2)
print("hello" if len(sys.argv) == 1 else "hello, " + sys.argv[1])
"""
                Path("hello.py").write_text(script)
            report = None
    if report is not None:
        Path(args[args.index("--output-last-message") + 1]).write_text(json.dumps(report))
    print(json.dumps({"type": "turn.started"}))
    print(json.dumps({"type": "turn.completed", "usage": {"input_tokens": 1, "output_tokens": 1}}))
    sys.exit(0)
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
    mode = os.environ.get("BOSS_AUTOPILOT_MODE")
    if mode in ("intake_repair", "intake_exhausted"):
        assert intake["check_config"]["argv"] == ["python3", "check.py"]
        assert intake["previous_failure"] is None if attempt == 1 else intake["previous_failure"]["validation_code"] == "report_too_large"
    original = {key: intake[key] for key in ("base_commit", "documents", "check_config")}
    input_hash = hashlib.sha256(json.dumps(original, sort_keys=True).encode()).hexdigest()
    with calls.open("a") as log:
        log.write(json.dumps({"kind": "intake", "attempt": attempt, "input_hash": input_hash,
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
    if mode in ("timeout_source", "network_source", "provider_source"):
        Path("partial-only.txt").write_text("retained bootstrap input\n")
        Path("result.txt").write_text("partial\n")
        if mode == "timeout_source":
            time.sleep(30)
            sys.exit(2)
        if mode == "provider_source":
            print(json.dumps({"type": "error", "code": "rate_limit_exceeded"}), flush=True)
            sys.exit(1)
        assert not any("sandbox_workspace_write.network_access" in arg for arg in args)
        print(json.dumps({"type": "turn.completed", "usage": {"input_tokens": 1, "output_tokens": 1}}), flush=True)
        sys.exit(0)
    assert args[args.index("--sandbox") + 1] == "workspace-write"
    if mode == "network_repair":
        assert "sandbox_workspace_write.network_access=true" in args
        assert "features.network_proxy.enabled=true" in args
        assert "features.network_proxy.allow_local_binding=true" in args
        domains = next(arg for arg in args if arg.startswith("features.network_proxy.domains="))
        assert "github.com" in domains and "repo.hex.pm" in domains and "*" not in domains
    cycle = data["cycle"]
    gate = Path(os.environ["BOSS_AUTOPILOT_GATES"]) / f"{name}-{cycle}"
    gate.with_suffix(".waiting").write_text(str(os.getpid()))
    while not gate.with_suffix(".release").exists():
        time.sleep(0.02)
    if mode in ("timeout_repair", "network_repair"):
        assert Path("partial-only.txt").read_text() == "retained bootstrap input\n"
        assert data["plan"]["acceptance"] == ["Create result.txt"]
        assert Path("result.txt").read_text() == ("partial\n" if cycle == 1 else "one-1\n")
    elif cycle > 1:
        assert data["previous_feedback"]["kind"] == "review"
    Path("result.txt").write_text(f"{name}-{cycle}\n")
else:
    assert args[args.index("--sandbox") + 1] == "read-only"
    if mode in ("network_source", "network_repair"):
        assert not any("sandbox_workspace_write.network_access" in arg for arg in args)
    if kind == "resolve":
        if mode in ("timeout_repair", "network_repair"):
            assert Path("partial-only.txt").read_text() == "retained bootstrap input\n"
            assert data["plan"]["acceptance"] == ["Create result.txt"]
            assert data["candidate_commit"] != data["base_commit"]
            if Path("result.txt").read_text() == "partial\n":
                assert "CHECK_OUTPUT_FOR_TIMEOUT_REPAIR" in json.dumps(data["previous_feedback"])
        report = {"summary": "Use the saved output requirement", "steps": ["Write result.txt as specified"],
                  "assumptions": ["Preserve the existing text format"], "external_action": "The implementation runner needs dependency network access." if mode == "network_source" else None}
    elif kind == "plan":
        report = {"summary": "Write result", "steps": ["Write result.txt"],
                  "acceptance": [] if mode == "invalid_first" and name == "one" else ["Create result.txt"], "file_scopes": None}
        if mode == "autonomy_plan" and name == "one" and not data.get("resolution"):
            report["clarification"] = "Which existing output format should be used?"
    else:
        assert data["check_receipt"]["exit_code"] == 0
        assert "result.txt" in data["diff"]
        prior = [json.loads(line) for line in (root / "calls").read_text().splitlines()]
        review_count = sum(call.get("kind") == "review" and call.get("task") == name for call in prior)
        reject = mode == "repair" and name == "one" and not data["previous_feedback"] or mode in ("timeout_repair", "network_repair") and review_count == 1
        report = {"verdict": "changes_requested" if reject else "approved", "summary": "Checked result",
                  "acceptance": [{"criterion": "Create result.txt", "status": "failed" if reject else "passed", "evidence": "Inspected result.txt"}],
                  "issues": [{"criterion": "Create result.txt", "message": "Correct result.txt"}] if reject else []}
    Path(args[args.index("--output-last-message") + 1]).write_text(json.dumps(report))
print(json.dumps({"type": "turn.completed", "usage": {"input_tokens": 1, "output_tokens": 1}}), flush=True)
