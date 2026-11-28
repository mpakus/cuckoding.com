"""Release promotion checks without GitHub or Apple credentials."""
from io import BytesIO
import json
import os
from pathlib import Path
import shutil
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import github_release as release


TAG = "v0.1.0-rc.3"
SHA = "abcdef1234" * 4


class ReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        directory = self.root / "candidate"
        directory.mkdir()
        self.archive = directory / f"boss-{TAG[1:]}.tar.gz"
        self.package(SHA, "false", "arm64")
        self.changelog = f"## {TAG[1:]} — 2026-11-28\n\nRelease notes.\n\n## 0.0.1\n\nOlder notes."
        self.draft = None
        self.remote_files = {}
        self.calls = []

    def package(self, commit, dirty, arch):
        text = f"BOSS {TAG[1:]}\nSource commit: {commit}\nSource local changes: {dirty}\nArchitecture: {arch}\n".encode()
        with tarfile.open(self.archive, "w:gz") as tar:
            member = tarfile.TarInfo("BUILD_INFO")
            member.size = len(text)
            tar.addfile(member, BytesIO(text))
        self.archive.with_name("SHA256SUMS").write_text(
            f"{release.sha256(self.archive)}  _build/prod/{self.archive.name}\n")

    def test_only_exact_prerelease_can_explicitly_skip_signing(self):
        self.assertEqual(release.mode_for(TAG, ""), "signed")
        self.assertEqual(release.mode_for(TAG, TAG), "archive")
        with self.assertRaises(SystemExit):
            release.mode_for("v1.0.0", "v1.0.0")

    def test_source_provenance_and_checksum(self):
        directory = self.archive.parent
        self.assertEqual(release.verify_archive(directory, TAG, SHA), self.archive)
        for commit, dirty, arch in [("old", "false", "arm64"), (SHA, "true", "arm64"), (SHA, "false", "x86_64")]:
            self.package(commit, dirty, arch)
            with self.assertRaises(SystemExit):
                release.verify_archive(directory, TAG, SHA)
        self.package(SHA, "false", "arm64")
        self.archive.with_name("SHA256SUMS").write_text("corrupted")
        with self.assertRaises(SystemExit):
            release.verify_archive(directory, TAG, SHA)

    def test_notes_cover_only_selected_version(self):
        notes = release.release_notes(TAG, self.changelog, "archive", SHA)
        self.assertIn("Release notes.", notes)
        self.assertIn("unsigned", notes)
        self.assertNotIn("Older notes.", notes)
        with self.assertRaises(SystemExit):
            release.release_notes("v2.0.0", self.changelog, "signed", SHA)

    def fake_gh(self, command, operation, tag, *args):
        self.assertEqual((command, tag), ("release", TAG))
        self.calls.append(operation)
        if operation == "create":
            notes = args[args.index("--notes-file") + 1].read_text()
            self.draft = dict(tag_name=tag, prerelease=True, draft=True, body=notes,
                              assets=[], html_url="https://example.invalid/release")
        elif operation == "upload":
            asset = Path(args[0])
            self.assertNotIn(asset.name, self.remote_files)
            self.remote_files[asset.name] = asset.read_bytes()
            self.draft["assets"].append(dict(name=asset.name, digest="sha256:" + release.sha256(asset)))
        elif operation == "edit":
            self.assertIn("--draft=false", args)
            self.draft["draft"] = False
        elif operation == "download":
            folder = args[args.index("--dir") + 1]
            folder.mkdir()
            for name, data in self.remote_files.items():
                (folder / name).write_bytes(data)
        else:
            self.fail(f"Unexpected gh operation: {operation}")

    def test_archive_publication_and_public_replay(self):
        self.addCleanup(os.chdir, os.getcwd())
        os.chdir(self.root)
        Path("mix.exs").write_text(f'      version: "{TAG[1:]}",\n')
        Path("CHANGELOG.md").write_text(self.changelog)
        with patch.dict(os.environ, GITHUB_OUTPUT=str(self.root / "outputs"), BOSS_ARCHIVE_ONLY_TAG=TAG), \
                patch.object(release, "check_tag"), patch.object(release, "release", lambda tag: self.draft), \
                patch.object(release, "gh", self.fake_gh):
            release.prepare(TAG, SHA, self.root)
            self.assertTrue(self.draft["draft"])
            release.finish(TAG, SHA, self.root)
            self.assertFalse(self.draft["draft"])
            self.assertEqual(self.calls, ["create", "upload", "upload", "edit", "download"])
            self.calls.clear()
            shutil.rmtree(self.root / "distribution")
            shutil.rmtree(self.root / "published")
            del os.environ["BOSS_ARCHIVE_ONLY_TAG"]
            release.prepare(TAG, SHA, self.root)
            release.finish(TAG, SHA, self.root)
            self.assertEqual(self.calls, ["download"])

    def test_mismatched_signed_archive_or_stapled_bytes_rejected(self):
        directory = self.root / "signed"
        directory.mkdir()
        image = directory / "boss.dmg"
        image.write_bytes(b"accepted signed bytes")
        intent = dict(tag=TAG, commit=SHA, source_archive_sha256=release.sha256(self.archive), submitted_sha256="a" * 64)
        (directory / "NOTARY_REQUEST.json").write_text(json.dumps(intent))
        report = dict(submission_id="fixture", status="Accepted", staple_validated=True,
                      gatekeeper_assessed=True, submitted_sha256="a" * 64, stapled_sha256=release.sha256(image))
        (directory / "NOTARIZATION.json").write_text(json.dumps(report))
        (directory / "NOTARY_SUBMISSION.json").write_text(json.dumps(dict(submission_id="fixture", submitted_sha256="a" * 64)))
        release.check_signed(directory, image, self.archive, TAG, SHA)
        with self.assertRaises(SystemExit):
            release.check_signed(directory, image, self.archive, TAG, "wrong-sha")
        image.write_bytes(b"unrelated")
        with self.assertRaises(SystemExit):
            release.check_signed(directory, image, self.archive, TAG, SHA)


if __name__ == "__main__":
    unittest.main()
