import importlib.machinery
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import sys

sys.dont_write_bytecode = True


class BuildInfoTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        loader = importlib.machinery.SourceFileLoader("build_info", "bin/build-info")
        spec = importlib.util.spec_from_loader(loader.name, loader)
        cls.builder = importlib.util.module_from_spec(spec)
        loader.exec_module(cls.builder)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="cuckoding-build-info-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root / "lib").mkdir()
        (self.root / "lib/app.ex").write_text("defmodule App, do: nil\n")
        (self.root / "assets").mkdir()
        (self.root / "assets/app.css").write_text("body {}\n")

    def test_input_digest_covers_new_files_modes_and_bytes_but_not_private_outputs(self):
        before = self.builder.input_digest(self.root)
        (self.root / "unrelated.age").write_text("unrelated fixture, never an input")
        (self.root / "unrelated.age").chmod(0)
        (self.root / ".ccoding").mkdir()
        (self.root / ".ccoding/private").write_text("private fixture")
        self.assertEqual(before, self.builder.input_digest(self.root))
        p = self.root / "lib/new.ex"
        p.write_text("new source")
        added = self.builder.input_digest(self.root)
        self.assertNotEqual(before, added)
        p.write_text("changed source")
        changed = self.builder.input_digest(self.root)
        self.assertNotEqual(added, changed)
        p.chmod(0o700)
        self.assertNotEqual(changed, self.builder.input_digest(self.root))

    def test_links_and_special_inputs_are_refused_without_following_them(self):
        p = self.root / "lib/link"
        p.symlink_to(self.root / "not-readable")
        with self.assertRaises(ValueError):
            self.builder.input_digest(self.root)
        p.unlink()
        import os
        os.mkfifo(p)
        with self.assertRaises(ValueError):
            self.builder.input_digest(self.root)

    def test_generated_json_never_follows_links_or_overwrites_receipts(self):
        target = self.root / "manifest.json"
        target.symlink_to(self.root / "elsewhere")
        with self.assertRaises(ValueError):
            self.builder.write_json(target, {"format": 1})
        target.unlink()
        self.builder.write_json(target, {"format": 1}, exclusive=True)
        with self.assertRaises(FileExistsError):
            self.builder.write_json(target, {"format": 2}, exclusive=True)
        self.assertEqual(json.loads(target.read_text()), {"format": 1})
        import os
        twin = self.root / "linked.json"
        os.link(target, twin)
        with self.assertRaises(ValueError):
            self.builder.write_json(target, {"format": 3})
        self.assertEqual(json.loads(twin.read_text()), {"format": 1})

    def test_verification_refuses_source_drift_and_mixed_generated_manifests(self):
        info = {"source_sha256": self.builder.input_digest(self.root), "source_revision": "a" * 40}
        paths = [self.root / "one.json", self.root / "two.json"]
        for path in paths:
            self.builder.write_json(path, info)
        self.builder.verify_inputs(self.root, info, paths, "a" * 40)
        self.builder.write_json(paths[1], {**info, "source_revision": "b" * 40})
        with self.assertRaises(ValueError):
            self.builder.verify_inputs(self.root, info, paths, "a" * 40)
        self.builder.write_json(paths[1], info)
        (self.root / "lib/app.ex").write_text("changed during build")
        with self.assertRaises(ValueError):
            self.builder.verify_inputs(self.root, info, paths, "a" * 40)


if __name__ == "__main__":
    unittest.main()
