#!/usr/bin/env python3
"""Finite local CLI fixture; never invokes a provider."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

signal.alarm(15)
args = sys.argv[1:]
assert args[args.index("--sandbox") + 1] == "read-only"
assert "--ephemeral" in args and "--ignore-user-config" in args
assert args[args.index("--ask-for-approval") + 1] == "never"
assert "resume" not in args
schema = Path(args[args.index("--output-schema") + 1])
assert json.loads(schema.read_text())["additionalProperties"] is False
output = Path(args[args.index("--output-last-message") + 1])
prompt = sys.stdin.read()
assert "candidate_commit" in prompt and "config_hash" in prompt
assert "diff --git" in prompt and "candidate" in prompt
marker = os.environ.get("BOSS_REVIEW_MARKER")

def emit(value):
    print(json.dumps(value), flush=True)

emit({"type": "turn.started"})
emit({"type": "item.completed", "item": {"type": "agent_message", "text": "SECRET_INTERMEDIATE_TEXT"}})
print("SECRET_REVIEW_STDERR", file=sys.stderr, flush=True)
mode = os.environ.get("BOSS_REVIEW_MODE", "approved")
report = {"verdict": "approved", "summary": "Implementation matches the saved task.", "acceptance": [{"criterion": "Create result.txt", "status": "passed", "evidence": "result.txt contains candidate"}], "issues": []}
if mode in ("changes_requested", "needs_spec_revision"):
    report["verdict"] = mode
    report["acceptance"][0]["status"] = "failed" if mode == "changes_requested" else "unclear"
    report["issues"] = [{"criterion": "Create result.txt", "message": "Specify the expected contents."}]
if mode == "late_output":
    def late_output(_signal, _frame):
        time.sleep(0.05)
        if marker:
            Path(marker + ".late").write_text("attempted")
        try:
            output.write_text(json.dumps(report))
        except FileNotFoundError:
            pass
        sys.exit(0)
    signal.signal(signal.SIGTERM, late_output)
if marker:
    Path(marker).write_text(json.dumps({"pid": os.getpid(), "output": str(output)}))
if mode in ("wait", "late_output"):
    while True:
        time.sleep(0.1)
if mode == "missing":
    pass
elif mode == "oversize":
    output.write_text("x" * 32769)
elif mode == "symlink":
    output.unlink()
    output.symlink_to(Path.cwd() / "result.txt")
elif mode == "duplicate":
    output.write_text(json.dumps(report)[:-1] + ',"verdict":"approved"}')
else:
    output.write_text(json.dumps(report))
if mode == "dirty":
    Path("result.txt").write_text("reviewer changed candidate")
elif mode == "head":
    subprocess.run(["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgSign=false", "commit", "--allow-empty", "-m", "drift"], check=True, stdout=subprocess.DEVNULL)
emit({"type": "turn.completed", "usage": {"input_tokens": 3, "output_tokens": 2}})
sys.exit(7 if mode == "fail" else 0)
