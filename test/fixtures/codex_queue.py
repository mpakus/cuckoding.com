#!/usr/bin/env python3
"""Hold each real implementation process behind its own finite test gate."""
import os
from pathlib import Path
import signal
import sys
import time

signal.alarm(60)
if "--output-schema" not in sys.argv:
    gate = Path(os.environ["BOSS_QUEUE_GATES"]) / Path.cwd().name
    gate.with_suffix(".waiting").write_text(str(os.getpid()))
    while not gate.with_suffix(".release").exists():
        time.sleep(0.02)

fixture = os.environ["BOSS_QUEUE_CODEX_FIXTURE"]
os.execv(sys.executable, [sys.executable, fixture, *sys.argv[1:]])
