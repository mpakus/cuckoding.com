"""Exercise the launcher's real OS lock without starting Phoenix or using app data."""
import fcntl
from pathlib import Path
import shutil
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


if __name__ == "__main__":
    unittest.main()
