"""Finite local check command; never invokes a provider."""
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

signal.alarm(15)
mode = sys.argv[1]
if mode == "pass":
    assert Path("result.txt").read_text() == "candidate"
    print("SECRET_CHECK_OUTPUT")
elif mode == "fail":
    sys.exit(7)
elif mode == "tracked":
    Path("result.txt").write_text("changed by check")
elif mode == "untracked":
    Path("unexpected.txt").write_text("changed by check")
elif mode == "head":
    subprocess.run(["git", "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false",
                    "commit", "--allow-empty", "-m", "fixture drift"], check=True)
elif mode == "wait":
    Path(sys.argv[2]).write_text(str(os.getpid()))
    while True:
        time.sleep(0.1)
else:
    sys.exit(9)
