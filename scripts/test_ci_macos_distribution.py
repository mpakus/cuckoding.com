"""Finite fixtures for the signing/notarization CI boundary; no Apple calls."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from uuid import uuid4

import ci_macos_distribution as release


class DistributionTest(unittest.TestCase):
    def test_identity_requires_an_exact_unique_match(self):
        name = "Developer ID Application: Example, Inc. (XYZ1234567)"
        fingerprint = "A" * 40
        listing = f'  1) {fingerprint} "{name}"\n'
        for selector in (name, fingerprint.lower()):
            self.assertEqual(release.certificate(selector, listing), fingerprint)
        for selector, candidates in (("Example", listing), (name, listing + listing),
                                     ("Developer ID Installer", listing)):
            with self.assertRaises(ValueError):
                release.certificate(selector, candidates)

    def test_failed_signing_restores_search_list_and_drops_keychain(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            original = "/Users/runner/Library/Keychains/example keychain"
            keychain = root / "signing.keychain-db"
            name = "Developer ID Application: Example (ABC1234567)"
            calls = []

            def fake_run(*args, **kwargs):
                calls.append(args)
                if args[1] == "list-keychains" and "-s" not in args:
                    return f'"{original}"\n'
                if args[1] == "create-keychain":
                    keychain.touch()
                if args[1] == "find-identity":
                    return f'  1) {"C" * 40} "{name}"\n'
                if args[0] == release.sys.executable:
                    self.assertFalse((root / "identity.p12").exists())
                    self.assertNotIn("GH_TOKEN", release.env_for())
                    self.assertNotIn("MACOS_CERTIFICATE_PASSWORD", release.env_for())
                    raise ValueError("fixture signing failure")
                return ""

            with patch.dict(os.environ, {"DEVELOPER_ID_APPLICATION": name, "MACOS_CERTIFICATE_BASE64": "Zg==",
                                         "MACOS_CERTIFICATE_PASSWORD": "private", "GH_TOKEN":"fixture"}):
                with patch.object(release, "run", fake_run), self.assertRaisesRegex(ValueError, "signing failure"):
                    release.sign(root / "archive", root / "out", root)
            self.assertEqual(calls[-2][1:], ("list-keychains", "-d", "user", "-s", original))
            self.assertEqual(calls[-1][1:], ("delete-keychain", str(keychain)))

    def test_submission_and_stapling(self):
        for failure in ("", "reservation", "lost reply", "rejected", "spctl"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as tmp:
                output = Path(tmp)
                (output / "boss.dmg").write_bytes(b"signed")
                (output / "SHA256SUMS").write_text(f"{release.digest(output / 'boss.dmg')}  boss.dmg\n")
                submission_id = str(uuid4())
                calls = []
                hook = output / "reserve"
                def fake_run(*args, **kwargs):
                    if args[0] == str(hook):
                        calls.append("reserve")
                        self.assertNotIn("MACOS_CERTIFICATE_PASSWORD", kwargs["env"])
                        self.assertEqual(Path(kwargs["env"]["BOSS_SUBMITTED_DMG"]).read_bytes(), b"signed")
                        if failure == "reservation":
                            raise ValueError("fixture denied reservation")
                    elif args[1] == "notarytool":
                        action = args[2]
                        calls.append(action)
                        if action == "submit":
                            if failure == "lost reply":
                                raise ValueError("fixture timed out")
                            return json.dumps({"id": submission_id})
                        if action == "wait":
                            receipt = json.loads((output / "NOTARIZATION.json").read_text())
                            self.assertEqual(receipt["submission_id"], submission_id)
                            return json.dumps({"id": submission_id, "status": "Invalid" if failure == "rejected" else "Accepted"})
                    elif args[1:3] == ("stapler", "staple"):
                        self.assertEqual(json.loads((output / "NOTARIZATION.json").read_text())["status"], "Accepted")
                        calls.append("staple")
                        (output / "boss.dmg").write_bytes(b"stapled")
                    elif args[0].endswith("spctl") and failure == "spctl":
                        raise ValueError("fixture denied Gatekeeper assessment")
                    return ""
                with patch.dict(os.environ, {"APPLE_API_KEY_ID":"fixture", "APPLE_API_ISSUER":"fixture",
                                             "MACOS_CERTIFICATE_PASSWORD":"fixture"}), patch.object(release, "run", fake_run):
                    if failure:
                        with self.assertRaises(ValueError):
                            release.notarize(output, output / "private.p8", hook)
                    else:
                        release.notarize(output, output / "private.p8", hook)
                self.assertEqual(calls.count("submit"), 0 if failure == "reservation" else 1)
                self.assertEqual(calls[:2], ["history", "reserve"])
                self.assertEqual((output / "boss-submitted.dmg").read_bytes(), b"signed")
                self.assertEqual(calls.count("staple"), int(failure in ("", "spctl")))
                self.assertEqual((output / "SHA256SUMS").exists(), not failure)
                if not failure:
                    receipt = json.loads((output / "NOTARIZATION.json").read_text())
                    self.assertEqual(receipt["stapled_sha256"], release.digest(output / "boss.dmg"))
                    self.assertTrue(receipt["gatekeeper_assessed"])


if __name__ == "__main__":
    unittest.main()
