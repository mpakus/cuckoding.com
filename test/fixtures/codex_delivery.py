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
if args == ["--config", 'model_provider="openai"', "debug", "models"]:
    catalog_mode = os.environ.get("BOSS_MODEL_CATALOG", "requested")
    if catalog_mode == "unavailable":
        sys.exit(1)
    if catalog_mode == "invalid":
        print('{"models":"RAW_CATALOG_SECRET_SENTINEL"}')
        sys.exit(0)
    if catalog_mode == "wait":
        Path(os.environ["BOSS_DELIVERY_FIXTURE"], "catalog-waiting").write_text(str(os.getpid()))
        while True:
            time.sleep(0.1)
    models = ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"] if catalog_mode == "installed" else ["gpt-6.1-sol", "gpt-6-astra", "gpt-6-luna"]
    print(json.dumps({"models": [{"slug": model, "visibility": "list", "supported_reasoning_levels": [{"effort": effort} for effort in ["medium", "high", "xhigh"]]} for model in models]}))
    sys.exit(0)
assert "--ephemeral" in args and "--ignore-user-config" in args
assert args[args.index("--ask-for-approval") + 1] == "never"
prompt = sys.stdin.read()
data = json.loads(prompt.split("BOSS delivery input (JSON):\n", 1)[1])
assert isinstance(data["check_config"]["argv"], list) and data["check_config"]["argv"]
mode = os.environ.get("BOSS_DELIVERY_MODE", "approved")
root = Path(os.environ["BOSS_DELIVERY_FIXTURE"])
schema = Path(args[args.index("--output-schema") + 1]) if "--output-schema" in args else None
kind = "resolve" if schema and schema.name == "resolution_schema.json" else "plan" if schema and schema.name == "plan_schema.json" else "review" if schema else "implement"
cycle = data.get("cycle", 0)
model = args[args.index("--model") + 1] if "--model" in args else None
effort = next((arg.split("=", 1)[1].strip('"') for arg in args if arg.startswith("model_reasoning_effort=")), None)
with (root / "calls").open("a") as calls:
    calls.write(json.dumps({"kind": kind, "cycle": cycle, "cwd": str(Path.cwd()), "target_commit": data.get("target_commit"),
                           "model": model, "reasoning_effort": effort, "resolution_attempt": data.get("resolution_attempt"),
                           "base_commit": data.get("base_commit"), "previous_candidate_commit": data.get("previous_candidate_commit"),
                           "has_previous_review": bool(data.get("previous_review")),
                           "source_review_id": (data.get("previous_feedback") or {}).get("source_review_id")}) + "\n")

def emit(value):
    print(json.dumps(value), flush=True)

emit({"type": "turn.started"})
emit({"type": "item.completed", "item": {"type": "agent_message", "text": "RAW_MODEL_SECRET_SENTINEL"}})
print("RAW_AGENT_STDERR_SECRET_SENTINEL", file=sys.stderr, flush=True)

if mode == "routing_auth":
    emit({"type": "error", "code": "invalid_api_key", "message": "RAW_MODEL_SECRET_SENTINEL"})
    sys.exit(1)

if mode == "routing_zero_error" and kind == "implement" and cycle == 1:
    Path("partial-only.txt").write_text("retained failed implementation\n")
    emit({"type": "error", "message": "RAW_MODEL_SECRET_SENTINEL failed with zero exit"})
    sys.exit(0)

if mode == "autonomy_zero_error":
    emit({"type": "error", "message": "RAW_MODEL_SECRET_SENTINEL failed with zero exit"})
    sys.exit(0)
if mode == "autonomy_malformed_wait":
    print("{invalid", flush=True)
    while True:
        time.sleep(0.1)

if (mode == "autonomy_persistent_sol" and model == "gpt-6.1-sol") or \
   (mode == "autonomy_models_exhausted" and model in ("gpt-6.1-sol", "gpt-6-astra")) or \
   (mode == "autonomy_model_unavailable" and kind == "plan" and not data.get("resolution")) or \
   (mode == "autonomy_resolver_unavailable" and kind == "resolve" and data["resolution_attempt"] == 1) or \
   (mode == "autonomy_review_unavailable" and kind == "review" and Path("result.txt").read_text() == "candidate-1\n"):
    emit({"type": "error", "code": "model_not_found", "message": "RAW_MODEL_SECRET_SENTINEL unavailable model"})
    sys.exit(7)

if (mode == "wait" and kind == "implement") or (mode in ("autonomy_wait_resolve", "autonomy_partial_wait_resolve") and kind == "resolve"):
    (root / ("waiting" if kind == "implement" else "resolver-waiting")).write_text(str(os.getpid()))
    while True:
        time.sleep(0.1)

if kind == "implement":
    assert args[args.index("--sandbox") + 1] == "workspace-write"
    assert data["plan"]["acceptance"] == ["Create result.txt"]
    if mode in ("autonomy_partial", "autonomy_luna_unavailable", "autonomy_partial_wait_resolve") and cycle == 1:
        Path("result.txt").write_text("unverified partial work\n")
        Path("partial-only.txt").write_text("retained failed implementation\n")
        emit({"type": "turn.failed", "error": {"message": "RAW_MODEL_SECRET_SENTINEL model failure"}})
        sys.exit(7)
    if cycle == 1 and (data.get("previous_feedback") or {}).get("source_review_id"):
        assert Path("result.txt").read_text() == "candidate-3\n"
        assert Path("first-only.txt").read_text() == "retained first attempt\n"
        feedback = data["previous_feedback"]
        assert feedback["report"]["verdict"] == "changes_requested"
        assert feedback["report"]["issues"][0]["message"] == "Correct result.txt contents"
        assert feedback["check_receipt"]["output_complete"] is True
        assert "CHECK_STDOUT_SECRET_SENTINEL" in feedback["check_output"]["stdout"]
        assert "CHECK_STDERR_SECRET_SENTINEL" in feedback["check_output"]["stderr"]
    if cycle > 1:
        assert data["previous_feedback"]["kind"] in ("checks", "review", "implementation", "merge_conflict")
        if data["previous_feedback"]["kind"] == "implementation":
            assert Path("result.txt").read_text() == "base"
            assert not Path("partial-only.txt").exists()
        elif data["previous_feedback"]["kind"] == "merge_conflict":
            assert data["base_commit"] == data["previous_feedback"]["target_commit"]
            assert Path("result.txt").read_text() != "candidate-1\n"
        else:
            assert Path("first-only.txt").read_text() == "retained first attempt\n"
            check = data["previous_feedback"]["check_receipt"]
            assert check["output_complete"] is True and len(check["output_hash"]) == 64
            assert check["stdout_bytes"] > 0 and check["stderr_bytes"] > 0
    Path("first-only.txt").write_text("retained first attempt\n")
    if mode == "retry_unchanged":
        contents = Path("result.txt").read_text().rstrip("\n")
    elif mode == "retry_reject_always":
        contents = f"retry-candidate-{cycle}"
    else:
        contents = "unchanged" if mode in ("repeated", "check_repeated") or (mode == "autonomy_repeated" and cycle < 3) else f"candidate-{cycle}"
    Path("result.txt").write_text(contents + "\n")
else:
    assert args[args.index("--sandbox") + 1] == "read-only"
    output = Path(args[args.index("--output-last-message") + 1])
    if kind == "resolve":
        assert model in ("gpt-6-astra", "gpt-6.1-sol", "gpt-5.6-sol", "gpt-5.6-terra")
        feedback = data["previous_feedback"]
        if feedback["kind"] == "implementation":
            assert Path("result.txt").read_text() == "base"
            assert not Path("partial-only.txt").exists()
        elif feedback["kind"] == "merge_conflict":
            assert feedback["outcome"] == "merge_conflict"
            assert len(feedback["target_commit"]) in (40, 64)
            assert len(feedback["original_candidate"]) in (40, 64)
            assert feedback["target_commit"] != feedback["original_candidate"]
        elif feedback["kind"] != "plan":
            assert (feedback.get("check_receipt") or feedback["receipt"])["output_complete"] is True
            check_output = feedback.get("check_output") or feedback["output"]
            assert "CHECK_STDOUT_SECRET_SENTINEL" in check_output["stdout"]
            assert "CHECK_STDERR_SECRET_SENTINEL" in check_output["stderr"]
        report = {"summary": "Resolve the exact reported issue", "steps": ["Write result.txt and retain all acceptance criteria"],
                  "assumptions": ["Use the repository convention for output"], "external_action": None}
        if mode in ("autonomy_external", "needs_plan", "needs_spec"):
            report["external_action"] = "Which feature should this workflow deliver?" if mode == "needs_plan" else "Clarify expected output"
        if mode == "autonomy_invalid_resolver" and data["resolution_attempt"] == 1:
            report["steps"] = []
    elif kind == "plan":
        report = {"summary": "Create the result", "steps": ["Write result.txt"], "acceptance": ["Create result.txt"], "file_scopes": None}
        if mode == "needs_plan" or (mode in ("autonomy_plan", "autonomy_external", "autonomy_invalid_resolver", "autonomy_resolver_unavailable") and not data.get("resolution")):
            report = {"summary": "Workflow guidance", "steps": [], "acceptance": [],
                      "file_scopes": None, "clarification": "Which feature should this workflow deliver?"}
        if data.get("previous_plan") and data.get("previous_review"):
            assert data["previous_plan"]["acceptance"] == report["acceptance"]
            assert data["previous_review"]["verdict"] == "changes_requested"
            assert data["previous_review"]["issues"][0]["message"] == "Correct result.txt contents"
            assert len(data["previous_candidate_commit"]) == 40
            assert "first-only.txt" in data["previous_diff"] and "result.txt" in data["previous_diff"]
            assert data["base_commit"] != data["previous_candidate_commit"]
            if mode == "retry_plan_changed":
                report["acceptance"] = ["Weaker replacement criterion"]
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
        if mode == "autonomy_invalid_plan" and not data.get("resolution"):
            report["acceptance"] = []
        if mode in ("autonomy_small", "autonomy_luna_unavailable"):
            report["complexity"] = "small"
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
        reject = mode in ("reject_always", "repeated", "retry_unchanged", "retry_reject_always") or (mode in ("reject_once", "autonomy_wait_resolve") and first) or (mode == "autonomy_repeated" and Path("result.txt").read_text() == "unchanged\n")
        unclear = mode == "needs_spec" or (mode == "autonomy_review" and first)
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
