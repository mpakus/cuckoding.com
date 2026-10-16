"""Reset only disposable app-owned fixtures; never use a real app/profile/project."""
from contextlib import redirect_stdout
import fcntl
import io
import json
import os
from pathlib import Path
import runpy
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "bin/reset-agents"
MARKER = ".ccoding-rebuild-v1"


class ResetAgentsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.parent = Path(self.temporary.name).resolve()
        self.root = self.parent / "data"
        self.root.mkdir(mode=0o700)
        (self.root / MARKER).write_text("ccoding-rebuild-v1\n")
        (self.root / "shell.lock").touch(mode=0o600)
        with sqlite3.connect(self.root / "foundation.db") as connection:
            connection.execute("CREATE TABLE commands(id TEXT, state TEXT)")
            connection.execute("CREATE TABLE battles(id TEXT, state TEXT)")
            for table in ("agent_connections", "arenas", "tabulae", "draft_tasks", "events"):
                connection.execute(f"CREATE TABLE {table}(id TEXT)")
                connection.execute(f"INSERT INTO {table} VALUES ('fixture')")
        private = self.root / "agents/fixture"
        private.mkdir(parents=True)
        (private / "private-profile").write_text("fixture-only-private-canary")
        (self.root / "runtime-home").mkdir()
        self.project = self.parent / "real-project"
        self.project.mkdir()
        (self.project / "keep.txt").write_text("external project stays intact")

    def run_reset(self, *args, text="RESET\n", env=None):
        return subprocess.run([sys.executable, str(SCRIPT), "--data-dir", str(self.root), *args],
                              input=text, text=True, capture_output=True, timeout=10, env=env)

    def archives(self):
        return list(self.parent.glob("data-reset-*"))

    def test_complete_archive_clean_root_and_restorable_database(self):
        (self.root / "external-link").symlink_to(self.project, target_is_directory=True)
        inode = (self.root / "shell.lock").stat().st_ino
        original = (self.root / "foundation.db").read_bytes()
        result = self.run_reset("--yes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Reset complete", result.stdout)
        self.assertNotIn("fixture-only-private-canary", result.stdout + result.stderr)
        self.assertEqual({p.name for p in self.root.iterdir()}, {MARKER, "shell.lock"})
        self.assertEqual((self.root / "shell.lock").stat().st_ino, inode)
        self.assertEqual((self.root / MARKER).stat().st_mode & 0o777, 0o600)
        [archive] = self.archives()
        self.assertEqual(archive.stat().st_mode & 0o777, 0o700)
        self.assertEqual((archive / "workspace/foundation.db").read_bytes(), original)
        self.assertTrue((archive / "workspace/external-link").is_symlink())
        self.assertEqual((archive / "reset.jsonl").stat().st_mode & 0o777, 0o600)
        self.assertEqual([json.loads(line)["event"] for line in (archive / "reset.jsonl").read_text().splitlines()],
                         ["workspace_reset.started", "workspace_reset.archived"])
        self.assertEqual((self.project / "keep.txt").read_text(), "external project stays intact")
        with sqlite3.connect(archive / "workspace/foundation.db") as connection:
            self.assertEqual(connection.execute("PRAGMA integrity_check").fetchone(), ("ok",))
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM arenas").fetchone(), (1,))
        # The fixed root lock is reusable; an already-reset empty workspace also resets safely.
        with (self.root / "shell.lock").open("r+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        self.assertEqual(self.run_reset("--yes").returncode, 0)

    def test_cancel_or_eof_changes_no_data(self):
        original = (self.root / "foundation.db").read_bytes()
        for answer in ("no\n", ""):
            result = self.run_reset(text=answer)
            self.assertEqual(result.returncode, 0)
            self.assertIn("Cancelled", result.stdout)
            self.assertEqual((self.root / "foundation.db").read_bytes(), original)
            self.assertEqual(self.archives(), [])

    def test_environment_selects_workspace_with_spaces(self):
        selected = self.parent / "data with spaces"
        self.root.rename(selected)
        result = subprocess.run([sys.executable, str(SCRIPT), "--yes"], capture_output=True,
                                text=True, timeout=10, env={**os.environ, "CCODING_DATA_DIR": str(selected)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual({p.name for p in selected.iterdir()}, {MARKER, "shell.lock"})
        self.assertEqual(len(list(self.parent.glob("data with spaces-reset-*"))), 1)

    def test_foreign_key_damage_is_refused(self):
        with sqlite3.connect(self.root / "foundation.db") as connection:
            connection.execute("CREATE TABLE parent(id INTEGER PRIMARY KEY)")
            connection.execute("CREATE TABLE child(parent_id INTEGER REFERENCES parent(id))")
            connection.execute("INSERT INTO child VALUES (999)")
        result = self.run_reset("--yes")
        self.assertEqual(result.returncode, 1)
        self.assertIn("foreign-key check failed", result.stderr)
        self.assertEqual(self.archives(), [])

    def test_running_owner_and_unresolved_work_are_refused(self):
        with (self.root / "shell.lock").open("r+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_reset("--yes")
            self.assertIn("Quit it first", result.stderr)
            self.assertEqual(result.returncode, 1)
        for table, state in (("commands", "running"), ("battles", "needs_attention"), ("battles", "paused")):
            with sqlite3.connect(self.root / "foundation.db") as connection:
                connection.execute(f"INSERT INTO {table} VALUES ('busy', ?)", (state,))
            result = self.run_reset("--yes")
            self.assertEqual(result.returncode, 1)
            self.assertIn("Finish/stop", result.stderr)
            with sqlite3.connect(self.root / "foundation.db") as connection:
                connection.execute(f"DELETE FROM {table} WHERE id='busy'")
        self.assertEqual(self.archives(), [])

    def test_links_unknown_markers_and_checkout_roots_are_refused(self):
        link = self.parent / "linked-data"
        link.symlink_to(self.root, target_is_directory=True)
        result = subprocess.run([sys.executable, str(SCRIPT), "--data-dir", str(link), "--yes"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("canonical", result.stderr)
        (self.root / MARKER).write_text("unknown\n")
        self.assertIn("Unrecognized", self.run_reset("--yes").stderr)
        (self.root / MARKER).write_text("ccoding-rebuild-v1\n")
        (self.root / ".git").mkdir()
        self.assertIn("project checkout", self.run_reset("--yes").stderr)
        self.assertEqual(self.archives(), [])

    def test_corrupt_or_linked_sqlite_and_sidecars_are_refused(self):
        database = self.root / "foundation.db"
        original = database.read_bytes()
        database.write_bytes(b"broken sqlite")
        self.assertNotEqual(self.run_reset("--yes").returncode, 0)
        database.write_bytes(original)
        external = self.parent / "external-db"
        external.write_bytes(original)
        database.unlink()
        database.symlink_to(external)
        self.assertIn("unsafe storage file", self.run_reset("--yes").stderr)
        database.unlink()
        database.write_bytes(original)
        (self.root / "foundation.db-wal").symlink_to(external)
        self.assertIn("unsafe storage file", self.run_reset("--yes").stderr)
        self.assertEqual(external.read_bytes(), original)
        self.assertEqual(self.archives(), [])

    def test_mid_reset_failure_retains_archive_and_invalidates_startup_marker(self):
        functions = runpy.run_path(str(SCRIPT))
        rename = os.rename
        moved = []

        def fail_after_marker(source, target):
            if moved:
                raise OSError("injected move failure")
            rename(source, target)
            moved.append(source)

        with patch.object(sys, "argv", [str(SCRIPT), "--data-dir", str(self.root), "--yes"]), \
             patch("os.rename", side_effect=fail_after_marker), redirect_stdout(io.StringIO()), \
             self.assertRaisesRegex(OSError, "injected"):
            functions["main"]()
        self.assertFalse((self.root / MARKER).exists())
        [archive] = self.archives()
        self.assertEqual((archive / "workspace" / MARKER).read_text(), "ccoding-rebuild-v1\n")
        self.assertEqual(len((archive / "reset.jsonl").read_text().splitlines()), 1)
        self.assertTrue((self.root / "foundation.db").exists())
        self.assertNotEqual(self.run_reset("--yes").returncode, 0)


if __name__ == "__main__":
    unittest.main()
