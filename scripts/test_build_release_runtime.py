#!/usr/bin/env python3
"""Finite safety checks; actual upstream compilation is a separate acceptance run."""
import hashlib
import io
import os
import signal
import sys
import time
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import build_release_runtime as runtime


class RuntimeBuildTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="boss-runtime-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def archive(self, name="source/file", link=None):
        path = self.root / "source.tar.gz"
        with tarfile.open(path, "w:gz") as archive:
            entry = tarfile.TarInfo(name)
            if link is None:
                entry.size = 7
                archive.addfile(entry, io.BytesIO(b"fixture"))
            else:
                entry.type = tarfile.SYMTYPE
                entry.linkname = link
                archive.addfile(entry)
        return path, {"directory": "source", "bytes": path.stat().st_size,
                      "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

    def test_size_and_hash_are_checked_before_extraction(self):
        archive, source = self.archive()
        for changed in (dict(source, bytes=0), dict(source, sha256="0" * 64)):
            destination = self.root / "unpack"
            with self.assertRaises(ValueError):
                runtime.unpack(archive, changed, destination)
            self.assertFalse(destination.exists())
        extracted = runtime.unpack(archive, source, self.root / "valid")
        self.assertEqual((extracted / "file").read_bytes(), b"fixture")

    def test_traversal_and_outside_symlinks_are_refused(self):
        for index, (name, link) in enumerate((("../outside", None), ("source/link", "../../outside"))):
            archive, source = self.archive(name, link)
            with self.assertRaises(tarfile.FilterError):
                runtime.unpack(archive, source, self.root / str(index))
            self.assertFalse((self.root / "outside").exists())

    @patch.object(runtime.sys, "platform", "darwin")
    @patch.object(runtime.platform, "machine", return_value="arm64")
    def test_existing_root_is_never_modified(self, _machine):
        output = self.root / "existing"
        output.mkdir()
        marker = output / "keep"
        marker.write_text("existing")
        with patch.object(runtime, "run") as run:
            with self.assertRaises(FileExistsError):
                runtime.main(output, 4)
            run.assert_not_called()
        self.assertEqual(list(output.iterdir()), [marker])
        self.assertEqual(marker.read_text(), "existing")

    @patch.object(runtime.sys, "platform", "darwin")
    @patch.object(runtime.platform, "machine", return_value="arm64")
    def test_failed_build_keeps_owned_root_without_complete_marker(self, _machine):
        output = self.root / "failed"
        marker = self.root / "keep"
        marker.write_text("unrelated")
        with patch.object(runtime, "run", side_effect=subprocess.CalledProcessError(1, ["fixture"])), \
             patch.object(runtime.shutil, "rmtree") as remove:
            with self.assertRaises(subprocess.CalledProcessError):
                runtime.main(output, 4)
            remove.assert_not_called()
        self.assertTrue((output / "build").is_dir())
        self.assertFalse((output / "RUNTIME_INFO.json").exists())
        self.assertEqual(marker.read_text(), "unrelated")


    @unittest.skipUnless(hasattr(os, "killpg"), "requires POSIX process groups")
    def test_timeout_and_failure_kill_descendants(self):
        for fail in (False, True):
            with self.subTest(nonzero_exit=fail):
                case = self.root / str(fail)
                case.mkdir()
                ready = case / "child.ready"
                child_pid = case / "child.pid"
                child = ("import os,signal,time;from pathlib import Path;"
                         "signal.signal(signal.SIGTERM,signal.SIG_IGN);"
                         f"Path({str(child_pid)!r}).write_text(str(os.getpid()));"
                         f"Path({str(ready)!r}).touch();time.sleep(30)")
                program = ("import subprocess,sys,time\nfrom pathlib import Path\n"
                           f"subprocess.Popen([sys.executable,'-c',{child!r}])\n"
                           f"while not Path({str(ready)!r}).exists(): time.sleep(0.01)\n"
                           + ("sys.exit(7)\n" if fail else "time.sleep(30)\n"))
                descendant = None

                def live():
                    state = subprocess.run(["/bin/ps", "-o", "stat=", "-p", str(descendant)],
                                           capture_output=True, text=True, check=False).stdout.strip()
                    return bool(state) and not state.startswith("Z")

                try:
                    expected = subprocess.CalledProcessError if fail else subprocess.TimeoutExpired
                    with self.assertRaises(expected):
                        runtime.run([sys.executable, "-c", program], case, os.environ,
                                    case / "fixture.log", timeout=1)
                    self.assertTrue(ready.exists())
                    descendant = int(child_pid.read_text())
                    deadline = time.monotonic() + 3
                    while live() and time.monotonic() < deadline:
                        time.sleep(0.02)
                    self.assertFalse(live(), "owned descendant survived")
                finally:
                    if descendant is not None and live():
                        os.kill(descendant, signal.SIGKILL)


if __name__ == "__main__":
    unittest.main()
