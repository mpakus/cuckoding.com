"""Sign and notarize the tag workflow's verified BOSS archive on a hosted Mac."""
import base64
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import tempfile
from uuid import UUID

from sign_macos_release import digest


def env_for(*names):
    keys = ("PATH", "HOME", "TMPDIR", "LANG", "LC_ALL", "USER", "LOGNAME", "DEVELOPER_DIR", *names)
    return {key: os.environ[key] for key in keys if key in os.environ}


def run(*args, timeout=120, env=None):
    # Several security commands take a password as an argument. Neither command
    # lines nor their unfiltered output belong in a release log.
    try:
        result = subprocess.run(args, env=env if env is not None else env_for(),
                                capture_output=True, check=True, timeout=timeout)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        raise ValueError(f"{Path(args[0]).name} {Path(str(args[1])).name} failed or timed out") from None
    return result.stdout.decode()


def decoded_file(name, path):
    raw = base64.b64decode("".join(os.environ[name].split()), validate=True)
    if not raw:
        raise ValueError(f"Empty {name}")
    with path.open("xb") as stream:
        stream.write(raw)


def certificate(selection, listing):
    matches = []
    for fingerprint, name in re.findall(r'^\s*\d+\) ([0-9A-Fa-f]{40}) "([^"\n]+)"$', listing, re.M):
        if name.startswith("Developer ID Application: ") and (selection == name or selection.upper() == fingerprint.upper()):
            matches.append(fingerprint.upper())
    if len(matches) != 1:
        raise ValueError("Expected exactly one selected Developer ID Application identity in the imported keychain")
    return matches[0]


def sign(archive, output, temp):
    keychain = str(temp / "signing.keychain-db")
    password = secrets.token_hex(32)
    security = "/usr/bin/security"
    original = shlex.split(run(security, "list-keychains", "-d", "user"))
    cert = temp / "identity.p12"
    decoded_file("MACOS_CERTIFICATE_BASE64", cert)
    try:
        run(security, "create-keychain", "-p", password, keychain)
        run(security, "set-keychain-settings", "-lut", "7200", keychain)
        run(security, "unlock-keychain", "-p", password, keychain)
        run(security, "import", str(cert), "-k", keychain, "-f", "pkcs12", "-P",
            os.environ["MACOS_CERTIFICATE_PASSWORD"], "-x", "-T", "/usr/bin/codesign")
        cert.unlink()
        run(security, "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, keychain)
        selected = certificate(os.environ["DEVELOPER_ID_APPLICATION"],
                               run(security, "find-identity", "-v", "-p", "codesigning", keychain))
        run(security, "list-keychains", "-d", "user", "-s", keychain, *original)
        run(sys.executable, str(Path(__file__).with_name("sign_macos_release.py")), str(archive),
            "--identity", selected, "--output", str(output), timeout=1800)
    finally:
        try:
            run(security, "list-keychains", "-d", "user", "-s", *original)
        finally:
            if Path(keychain).exists():
                run(security, "delete-keychain", keychain)


def save_receipt(output, receipt):
    # Preserve the previous valid receipt if the runner stops during a write.
    temp = output / "NOTARIZATION.json.tmp"
    temp.write_text(json.dumps(receipt, sort_keys=True, indent=2) + "\n")
    temp.replace(output / "NOTARIZATION.json")


def notarize(output, key, hook):
    auth = ("--key", str(key), "--key-id", os.environ["APPLE_API_KEY_ID"], "--issuer", os.environ["APPLE_API_ISSUER"])
    xcrun = "/usr/bin/xcrun"
    run(xcrun, "notarytool", "history", *auth, "--output-format", "json")
    submitted = output / "boss-submitted.dmg"
    image = output / "boss.dmg"
    image.rename(submitted)
    original_sums = output / "SHA256SUMS"
    (output / "PRE_STAPLE_SHA256SUMS").write_text(
        original_sums.read_text().replace("  boss.dmg\n", "  boss-submitted.dmg\n"))
    original_sums.unlink()
    receipt = {"submitted_sha256": digest(submitted), "status": "intent"}
    save_receipt(output, receipt)

    # The caller's exclusive draft asset survives a timeout, job cancellation,
    # or a new runner. A duplicate reservation stops before Apple's submit.
    hook_env = env_for("GH_TOKEN", "GH_REPO", "GITHUB_REPOSITORY", "TAG", "GITHUB_REF_NAME",
                       "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_SHA")
    hook_env["BOSS_SUBMITTED_DMG"] = str(submitted)
    run(str(hook), str(submitted), env=hook_env)
    submitted_result = json.loads(run(xcrun, "notarytool", "submit", str(submitted), *auth,
                                      "--no-wait", "--output-format", "json", timeout=1200))
    submission_id = str(UUID(submitted_result["id"]))
    receipt.update(submission_id=submission_id, status="submitted")
    save_receipt(output, receipt)
    print(f"Apple submission ID {submission_id}, DMG sha256 {receipt['submitted_sha256']}", flush=True)
    run(str(hook), str(submitted), submission_id, env=hook_env)
    status = json.loads(run(xcrun, "notarytool", "wait", submission_id, *auth,
                            "--timeout", "30m", "--output-format", "json", timeout=1900))
    if status.get("id", "").lower() != submission_id or status.get("status") != "Accepted":
        raise ValueError(f"Submission {submission_id} has no matching Accepted receipt")
    receipt["status"] = "Accepted"
    save_receipt(output, receipt)
    shutil.copyfile(submitted, image)
    if digest(image) != receipt["submitted_sha256"]:
        raise ValueError("Submitted image changed before stapling")
    run(xcrun, "stapler", "staple", str(image))
    run(xcrun, "stapler", "validate", str(image))
    run("/usr/bin/codesign", "--verify", "--strict", str(image))
    run("/usr/sbin/spctl", "--assess", "--verbose=2", "--type", "open", "--context", "context:primary-signature", str(image))
    receipt.update(stapled_sha256=digest(image), staple_validated=True, gatekeeper_assessed=True)
    save_receipt(output, receipt)
    (output / "SHA256SUMS").write_text(f"{receipt['stapled_sha256']}  boss.dmg\n")


def main(archive, output):
    for name in ("MACOS_CERTIFICATE_BASE64", "MACOS_CERTIFICATE_PASSWORD", "DEVELOPER_ID_APPLICATION",
                 "APPLE_API_KEY_BASE64", "APPLE_API_KEY_ID", "APPLE_API_ISSUER", "BOSS_NOTARY_INTENT_HOOK"):
        if not os.environ.get(name):
            raise ValueError(f"Missing {name}")
    hook = Path(os.environ["BOSS_NOTARY_INTENT_HOOK"])
    if not hook.is_absolute() or not hook.is_file() or not os.access(hook, os.X_OK):
        raise ValueError("Expected an absolute executable BOSS_NOTARY_INTENT_HOOK")
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="boss-ci-apple-") as private:
        temp = Path(private)
        sign(archive.resolve(strict=True), output, temp)
        key = temp / "notary.p8"
        decoded_file("APPLE_API_KEY_BASE64", key)
        notarize(output, key, hook)


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.platform != "darwin":
        sys.exit("Usage on macOS: ci_macos_distribution.sh ARCHIVE NEW_OUTPUT_DIRECTORY")
    try:
        main(Path(sys.argv[1]), Path(sys.argv[2]).absolute())
    except (KeyError, ValueError, OSError) as error:
        sys.exit(f"macOS distribution stopped: {error}")
