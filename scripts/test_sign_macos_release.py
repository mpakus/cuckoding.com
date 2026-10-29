#!/usr/bin/env python3
"""Fixture-only signing gates. This does not prove Developer ID execution."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import sign_macos_release as signing

IDENTITY = "A" * 40
TEAM = "A1B2C3D4E5"


class SigningTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="boss-signing-test-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        payload = self.root / "payload"
        for relative in ("erts-1/bin/beam.smp", "lib/boss-1/priv/native/boss_guardian", "lib/crypto.so"):
            target = payload / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(bytes.fromhex("cffaedfe") + b"fixture")
        (payload / "bin").mkdir()
        (payload / "bin/boss").write_text("fixture launcher")
        (payload / "LICENSES").mkdir()
        (payload / "LICENSES/BOSS-LICENSE").write_text("fixture license")
        (payload / "BUILD_INFO").write_text("BOSS fixture\nSource commit: " + "0" * 40 + "\nSource local changes: false\n")
        (payload / "alias").symlink_to("lib/crypto.so")
        self.archive = self.root / "boss.tar.gz"
        with tarfile.open(self.archive, "w:gz") as package:
            package.add(payload, arcname=".")
        self.before = self.archive.read_bytes()
        self.output = self.root / "output"
        self.calls = []
        self.signed = {}
        self.failure = None
        self.patch_run = patch.object(signing, "run", self.fake_run)
        self.patch_platform = patch.object(signing.sys, "platform", "darwin")
        self.patch_smoke = patch.object(signing, "smoke", self.fake_smoke)
        self.patch_smoke.start()
        self.addCleanup(self.patch_smoke.stop)
        self.patch_run.start()
        self.patch_platform.start()
        self.addCleanup(self.patch_run.stop)
        self.addCleanup(self.patch_platform.stop)

    def fake_run(self, *command, timeout=120):
        self.calls.append(command)
        self.assertLessEqual(timeout, 300)
        result = subprocess.CompletedProcess(command, 0, stdout=b"", stderr=b"")
        if command[0] == "/usr/bin/security":
            result.stdout = f'1) {IDENTITY} "Developer ID Application: Fixture ({TEAM})"\n'.encode()
        elif command[0] == "/usr/bin/codesign":
            path = Path(command[-1])
            if "--sign" in command:
                self.assertIn("--timestamp", command)
                self.assertNotIn("--deep", command)
                self.signed[path] = plistlib.loads(Path(command[command.index("--entitlements") + 1]).read_bytes()) if "--entitlements" in command else {}
            elif "--verify" in command:
                self.assertIn("--strict", command)
                self.assertIn(path, self.signed)
            elif "--entitlements" in command:
                entitlements = self.signed[path]
                if self.failure == "entitlements":
                    entitlements = {**entitlements, "com.apple.security.cs.disable-library-validation": True}
                result.stdout = plistlib.dumps(entitlements)
            else:
                fields = [f"TeamIdentifier={TEAM}", "Authority=Developer ID Application: Fixture", "Timestamp=fixture", "CodeDirectory v=20500 flags=0x10000(runtime)"]
                if self.failure in ("team", "timestamp", "runtime"):
                    prefix = {"team": "TeamIdentifier=", "timestamp": "Timestamp=", "runtime": "CodeDirectory "}[self.failure]
                    fields = [line for line in fields if not line.startswith(prefix)]
                result.stderr = ("\n".join(fields) + "\n").encode()
        elif command[0] == "/usr/bin/hdiutil":
            if command[1] == "create":
                contents = Path(command[command.index("-srcfolder") + 1])
                self.assertEqual([path.name for path in contents.iterdir()], ["boss"])
                Path(command[-1]).write_bytes(b"fixture DMG")
        else:
            self.fail(f"Unexpected tool: {command[0]}")
        return result

    def fake_smoke(self, archive):
        self.calls.append(("smoke", str(archive)))
        if self.failure == "smoke":
            raise AssertionError("fixture smoke failed")
        with tarfile.open(archive) as package:
            self.assertEqual(package.extractfile("./erts-1/bin/beam.smp").read()[:4], bytes.fromhex("cffaedfe"))

    def test_signed_payload_precedes_dmg_and_input_is_preserved(self):
        signing.main(self.archive, IDENTITY, self.output)
        self.assertEqual(self.archive.read_bytes(), self.before)
        native = {path.name: entitlements for path, entitlements in self.signed.items() if path.name != "boss.dmg"}
        self.assertEqual(len(native), 3)
        self.assertEqual(native.pop("beam.smp"), signing.JIT)
        self.assertEqual(list(native.values()), [{}, {}])
        smoke = next(index for index, command in enumerate(self.calls) if command[0] == "smoke")
        image = next(index for index, command in enumerate(self.calls) if command[:2] == ("/usr/bin/hdiutil", "create"))
        self.assertLess(smoke, image)
        info = json.loads((self.output / "SIGNING_INFO.json").read_text())
        self.assertEqual(info["native_images"], 3)
        self.assertEqual(info["notarization"], "not_performed")
        for line in (self.output / "SHA256SUMS").read_text().splitlines():
            checksum, name = line.split("  ")
            self.assertEqual(checksum, hashlib.sha256((self.output / name).read_bytes()).hexdigest())

    def test_existing_output_and_invalid_identity_are_refused(self):
        self.output.mkdir()
        marker = self.output / "keep"
        marker.write_text("existing")
        with self.assertRaises(FileExistsError):
            signing.main(self.archive, IDENTITY, self.output)
        self.assertEqual(marker.read_text(), "existing")
        for identity in ("-", "Developer ID Application: Fixture", "B" * 40):
            with self.assertRaises(ValueError):
                signing.main(self.archive, identity, self.root / "unused")
        self.assertFalse((self.root / "unused").exists())

    def test_incomplete_signing_or_smoke_never_creates_dmg_or_checksums(self):
        for failure in ("team", "timestamp", "runtime", "entitlements", "smoke"):
            with self.subTest(failure=failure):
                self.failure = failure
                self.calls.clear()
                destination = self.root / failure
                with self.assertRaises((AssertionError, ValueError)):
                    signing.main(self.archive, IDENTITY, destination)
                self.assertFalse((destination / "SHA256SUMS").exists())
                self.assertFalse((destination / "boss.dmg").exists())
                self.assertFalse(any(command[:2] == ("/usr/bin/hdiutil", "create") for command in self.calls))
                self.assertEqual(self.archive.read_bytes(), self.before)

    def test_archive_escape_is_refused(self):
        with tarfile.open(self.archive, "w:gz") as package:
            entry = tarfile.TarInfo("../escape")
            package.addfile(entry)
        with self.assertRaises(tarfile.FilterError):
            signing.main(self.archive, IDENTITY, self.output)
        self.assertFalse((self.root / "escape").exists())
        self.assertFalse((self.output / "SHA256SUMS").exists())


if __name__ == "__main__":
    unittest.main()
