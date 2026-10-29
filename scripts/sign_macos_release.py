#!/usr/bin/env python3
"""Sign a local BOSS archive and prepare a DMG; never upload or notarize it."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tarfile
import tempfile

from smoke_release import main as smoke


MACHO = {bytes.fromhex(value) for value in (
    "feedface", "cefaedfe", "feedfacf", "cffaedfe",
    "cafebabe", "bebafeca", "cafebabf", "bfbafeca")}
JIT = {"com.apple.security.cs.allow-jit": True}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(*command, timeout=120):
    return subprocess.run(command, check=True, capture_output=True, timeout=timeout)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def identity_team(identity):
    require(re.fullmatch(r"[A-Fa-f0-9]{40}", identity),
            "Identity must be an explicit Developer ID certificate SHA1 fingerprint")
    available = run("/usr/bin/security", "find-identity", "-v", "-p", "codesigning").stdout.decode()
    match = re.search(r'\b' + identity + r' "Developer ID Application: [^"\n]+ \(([A-Z0-9]{10})\)"',
                      available, re.IGNORECASE)
    require(match, "Selected Developer ID Application identity is unavailable")
    return match.group(1)


def verify(path, team, runtime=False, entitlements=None):
    run("/usr/bin/codesign", "--verify", "--strict", "--all-architectures", str(path))
    details = run("/usr/bin/codesign", "--display", "--verbose=4", str(path)).stderr.decode()
    require(f"TeamIdentifier={team}\n" in details, f"Wrong signing team: {path.name}")
    require("Authority=Developer ID Application:" in details, f"Missing Developer ID: {path.name}")
    require(re.search(r"^Timestamp=.+$", details, re.MULTILINE), f"Missing timestamp: {path.name}")
    if runtime:
        require(re.search(r"^CodeDirectory .*flags=0x[0-9a-f]+\(runtime\)", details, re.MULTILINE),
                f"Missing hardened runtime: {path.name}")
        raw = run("/usr/bin/codesign", "--display", "--entitlements", ":-", str(path)).stdout
        actual = plistlib.loads(raw) if raw.strip() else {}
        require(actual == (entitlements or {}), f"Unexpected entitlements: {path.name}")


def main(archive, identity, output):
    require(sys.platform == "darwin", "Signing requires macOS")
    archive = archive.resolve(strict=True)
    output = output.absolute()
    source_hash = digest(archive)
    team = identity_team(identity)
    output.mkdir(mode=0o700)  # Never overwrite or clean an existing destination.
    with tempfile.TemporaryDirectory(prefix="boss-signing-", dir=output) as temporary:
        staging = Path(temporary)
        release = staging / "payload/boss"
        release.mkdir(parents=True)
        with tarfile.open(archive) as package:
            package.extractall(release, filter="data")
        require((release / "bin/boss").is_file(), "BOSS launcher missing")
        require((release / "LICENSES/BOSS-LICENSE").is_file(), "BOSS license missing")
        provenance = (release / "BUILD_INFO").read_text()
        require(provenance.startswith("BOSS ") and "Source local changes: false\n" in provenance
                and re.search(r"^Source commit: [0-9a-f]{40}$", provenance, re.MULTILINE),
                "Expected clean BOSS build provenance")
        beams = list(release.glob("erts-*/bin/beam.smp"))
        guardians = list(release.glob("lib/boss-*/priv/native/boss_guardian"))
        require(len(beams) == 1 and len(guardians) == 1, "Expected one ERTS and native guardian")
        native = []
        for path in sorted(release.rglob("*")):
            if path.is_file() and not path.is_symlink():
                with path.open("rb") as stream:
                    if stream.read(4) in MACHO:
                        native.append(path)
        require(beams[0] in native and guardians[0] in native, "BEAM/guardian must be regular Mach-O files")
        entitlement_file = staging / "beam.plist"
        entitlement_file.write_bytes(plistlib.dumps(JIT))
        for path in native:
            arguments = ["/usr/bin/codesign", "--force", "--sign", identity, "--timestamp", "--options", "runtime"]
            if path == beams[0]:
                arguments.extend(["--entitlements", str(entitlement_file)])
            run(*arguments, str(path))
            verify(path, team, runtime=True, entitlements=JIT if path == beams[0] else {})
        evidence = {"source_archive_sha256": source_hash, "build_info": provenance,
                    "certificate_sha1": identity.upper(), "team_id": team,
                    "native_images": len(native), "hardened_runtime": True,
                    "beam_entitlements": JIT, "notarization": "not_performed"}
        encoded = json.dumps(evidence, indent=2, sort_keys=True) + "\n"
        (release / "SIGNING_INFO.json").write_text(encoded)
        signed_archive = staging / "signed.tar.gz"
        with tarfile.open(signed_archive, "w:gz") as package:
            package.add(release, arcname=".")
        smoke(signed_archive)
        # Smoke runs an extracted copy; package exactly the verified signed payload.
        for path in native:
            verify(path, team, runtime=True, entitlements=JIT if path == beams[0] else {})
        image = output / "boss.dmg"
        run("/usr/bin/hdiutil", "create", "-format", "UDZO", "-volname", "BOSS",
            "-srcfolder", str(release.parent), str(image), timeout=300)
        run("/usr/bin/codesign", "--sign", identity, "--timestamp",
            "--identifier", f"boss.release.{source_hash}", str(image))
        verify(image, team)
        run("/usr/bin/hdiutil", "verify", str(image), timeout=300)
        require(digest(archive) == source_hash, "Input archive changed during signing")
        info = output / "SIGNING_INFO.json"
        info.write_text(encoded)
        sums = "".join(f"{digest(path)}  {path.name}\n" for path in (image, info))
        (output / "SHA256SUMS").write_text(sums)
    print(f"Signed DMG prepared: {image}; notarization NOT performed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--identity", required=True, help="Developer ID Application certificate SHA1")
    parser.add_argument("--output", type=Path, required=True, help="New directory; existing paths are refused")
    args = parser.parse_args()
    try:
        main(args.archive, args.identity, args.output)
    except (AssertionError, OSError, ValueError, tarfile.TarError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Signing failed: {error}\nNo notarization was attempted.\n")
