"""Deterministic local CLI; never talks to a model or changes project files."""
import json
import os
import signal
import subprocess
import sys
import time


def event(kind):
    print(json.dumps({"type": kind}), flush=True)


mode = sys.argv[1]
if mode == "chunked":
    for chunk in [b'{"ty', b'pe":"thread.started"}\n{"type":', b'"turn.completed"}\n']:
        os.write(1, chunk)
        time.sleep(0.03)
    os.write(2, b"diagnostic\n")
elif mode == "invalid":
    os.write(1, b'{broken}\n')
elif mode == "oversized":
    os.write(1, b'x' * 65536)
elif mode == "unterminated":
    os.write(1, b'{"type":"turn.completed"}')
elif mode == "nonobject":
    os.write(1, b'[]\n')
elif mode == "failed":
    event("turn.completed")
    sys.exit(7)
elif mode == "protocol_failed":
    event("turn.failed")
elif mode == "missing_terminal":
    event("thread.started")
elif mode == "signal":
    os.kill(os.getpid(), signal.SIGTERM)
elif mode == "flood":
    for _ in range(1024):
        os.write(2, b'x' * 8192)
elif mode == "events":
    for _ in range(10000):
        event("item.completed")
elif mode == "stall":
    time.sleep(30)
elif mode == "busy":
    for _ in range(500):
        event("item.completed")
        time.sleep(0.01)
elif mode in ("tree", "orphan", "detached"):
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    child = subprocess.Popen(
        [sys.executable, "-c", "import time; time.sleep(30)"],
        start_new_session=mode == "detached",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    with open(sys.argv[2], "w") as handle:
        json.dump({"leader": os.getpid(), "child": child.pid}, handle)
    event("thread.started")
    if mode == "orphan":
        event("turn.completed")
    else:
        time.sleep(30)
else:
    raise ValueError(mode)
