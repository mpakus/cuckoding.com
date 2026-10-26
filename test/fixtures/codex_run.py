#!/usr/bin/env python3
"""Finite, local Codex-shaped CLI. Never imports a provider or uses a network."""
import json
import os
import signal
import sys
import time
from pathlib import Path

signal.alarm(30)
assert "--sandbox" in sys.argv and "workspace-write" in sys.argv
assert "--ask-for-approval" in sys.argv and "never" in sys.argv
assert sys.argv[-1] == "-"
Path("received-spec.txt").write_text(sys.stdin.read())
Path("result.txt").write_text("fixture change\n")
print(json.dumps({"type": "turn.started"}), flush=True)
sys.stderr.write("SECRET_DIAGNOSTIC\n")
sys.stderr.flush()
if os.environ.get("BOSS_CODEX_FIXTURE_MODE") == "wait":
    while True:
        time.sleep(0.1)
print(json.dumps({"type": "item.completed", "item": {"text": "SECRET_MODEL_OUTPUT"}}), flush=True)
print(json.dumps({"type": "turn.completed", "usage": {"input_tokens": 4, "output_tokens": 2}}), flush=True)
