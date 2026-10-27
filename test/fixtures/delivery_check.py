#!/usr/bin/env python3
"""Bounded check fixture with transient output."""
import os
from pathlib import Path
import signal
import sys

signal.alarm(10)
mode = os.environ.get("BOSS_DELIVERY_MODE", "approved")
text = Path("result.txt").read_text()
print("CHECK_STDOUT_SECRET_SENTINEL", flush=True)
print("CHECK_STDERR_SECRET_SENTINEL", file=sys.stderr, flush=True)
if mode == "check_invalid_utf8":
    sys.stdout.buffer.write(b"\xff")
    sys.stdout.flush()
if mode == "check_dirty":
    Path("result.txt").write_text("check changed candidate")
if mode == "check_repeated" or (mode == "check_once" and text == "candidate-1\n"):
    sys.exit(3)
