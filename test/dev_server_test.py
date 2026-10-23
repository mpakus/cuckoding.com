"""Exercise source-launcher ownership and signals in disposable fixtures only."""
import fcntl
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest


class DevServerLockTest(unittest.TestCase):
    def test_active_owner_is_explained_and_released_lock_is_reusable(self):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary).resolve()
            script = project / "bin/dev.server"
            script.parent.mkdir()
            shutil.copyfile(Path(__file__).resolve().parents[1] / "bin/dev.server", script)
            root = project / ".ccoding/ui-dev"
            root.mkdir(parents=True)
            data = root / "retained-data"
            data.write_bytes(b"keep this")
            with (root / "shell.lock").open("w") as lock:
                inode = (root / "shell.lock").stat().st_ino
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                result = subprocess.run([sys.executable, str(script), "--no-open"],
                                        capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 1)
                self.assertIn("already running for this checkout", result.stderr)
                self.assertIn("Ctrl-C", result.stderr)
                self.assertIn("Do not delete shell.lock", result.stderr)
                self.assertNotIn("Errno", result.stderr)
                self.assertNotIn("Traceback", result.stderr)
                self.assertEqual(data.read_bytes(), b"keep this")
                self.assertEqual({p.name for p in root.iterdir()}, {"shell.lock", "retained-data"})
                self.assertEqual((root / "shell.lock").stat().st_ino, inode)

            # The retained file alone must not block a later launch after its owner exits.
            result = subprocess.run([sys.executable, str(script), "--no-open"],
                                    capture_output=True, text=True, timeout=10)
            self.assertIn("Build the native helper first", result.stderr)
            self.assertNotIn("already running", result.stderr)
            self.assertEqual((root / "shell.lock").stat().st_ino, inode)
            self.assertEqual(data.read_bytes(), b"keep this")


CHILD = r'''
import io, json, os, queue, runpy, signal, subprocess, sys, threading, time, types
from pathlib import Path
script, requested_signal, phase = sys.argv[1:]
requested_signal = int(requested_signal)
module = runpy.run_path(script)
namespace = module["main"].__globals__
requests = []
waits = []

def stop():
    signal.raise_signal(requested_signal)
    signal.raise_signal(requested_signal)

class CriticalEvent(threading.Event):
    def wait(self, timeout=None):
        # Event.wait holds this non-reentrant condition briefly before sleeping.
        # A real signal in that window must not call Event.set on the same lock.
        with self._cond:
            if self._flag: return True
            stop()
        return False

class Thread:
    def __init__(self, target, daemon): self.target = target
    def start(self): self.target()

class Child:
    stdout = io.StringIO('CCODING_READY {"port":12345}\n')
    def poll(self): return None
    def wait(self, timeout): waits.append(timeout); return 0
    @property
    def pid(self): raise AssertionError("Fixture must never signal a process group")

def popen(*args, **kwargs):
    if phase == "startup": stop()
    return Child()

class ReadyQueue(queue.Queue):
    def get(self, **kwargs):
        value = super().get(**kwargs)
        if phase == "ready": stop()
        return value

def request(port, path, token):
    requests.append(path)
    if (path, phase) in [("/shell/bootstrap", "bootstrap"), ("/shell/open", "handoff")]: stop()
    return {"token":"disposable-fixture"}

namespace["queue"] = types.SimpleNamespace(Queue=ReadyQueue, Empty=queue.Empty)
namespace["threading"] = types.SimpleNamespace(Event=CriticalEvent, Thread=Thread)
namespace["time"] = types.SimpleNamespace(monotonic=time.monotonic, sleep=lambda _: stop())
namespace["subprocess"] = types.SimpleNamespace(Popen=popen, TimeoutExpired=subprocess.TimeoutExpired, DEVNULL=subprocess.DEVNULL, PIPE=subprocess.PIPE, STDOUT=subprocess.STDOUT)
namespace["tool"] = lambda name: "/usr/bin/true"
namespace["request"] = request
sys.argv = [script, "--port", "0"] + ([] if phase in ("bootstrap", "handoff") else ["--no-open"])
module["main"]()
assert waits == [8]
expected = [] if phase in ("startup", "ready") else ["/shell/bootstrap"] + (["/shell/open"] if phase == "handoff" else []) + ["/shell/quit"]
assert requests == expected, requests
root = Path(script).resolve().parent.parent / ".ccoding/ui-dev"
assert not list(root.glob("launch-*"))
with (root / "shell.lock").open("r+b") as lock:
    import fcntl
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
print("PASS: signal stopped startup/heartbeat and released the fixture lock")
'''


class DevServerSignalsTest(unittest.TestCase):
    def test_repeated_signals_during_startup_and_event_critical_section(self):
        for requested_signal in (signal.SIGINT, signal.SIGTERM):
            for phase in ("startup", "ready", "bootstrap", "handoff", "idle"):
                with self.subTest(signal=requested_signal.name, phase=phase):
                    with tempfile.TemporaryDirectory(prefix="cuckoding-dev-signals-") as temporary:
                        root = Path(temporary).resolve()
                        script = root / "bin/dev.server"
                        script.parent.mkdir()
                        shutil.copyfile("bin/dev.server", script)
                        helper = root / "desktop/src-tauri/target/release/bundle/macos/Cuckoding.app/Contents/MacOS/ccoding"
                        helper.parent.mkdir(parents=True)
                        helper.touch()
                        try:
                            result = subprocess.run(
                                [sys.executable, "-c", CHILD, str(script), str(int(requested_signal)), phase],
                                capture_output=True, text=True, timeout=2,
                            )
                        except subprocess.TimeoutExpired:
                            raise AssertionError("Shutdown handler deadlocked while holding its Event condition") from None
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertIn("PASS: signal", result.stdout)


if __name__ == "__main__":
    unittest.main()
