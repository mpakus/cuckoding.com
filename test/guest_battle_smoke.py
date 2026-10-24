"""Source OTP loop with the sealed native helper and real offline VMs; no inference.

Only fresh disposable fixtures; provider replies are explicit source-only adapters.
No production runtime/provider override, saved workspace or credentials are used.
"""
from pathlib import Path
import fcntl
import hashlib
import json
import os
import runpy
import sqlite3
import subprocess
import tempfile
import uuid

os.umask(0o077)
project = Path(__file__).resolve().parent.parent
app = project / "desktop/src-tauri/target/release/bundle/macos/Cuckoding.app"
helper = app / "Contents/MacOS/ccoding"
subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "--deep", str(app)], check=True, timeout=60)
info = json.loads(subprocess.check_output([str(helper), "--build-info"], timeout=5))
assert info["schema"] == 19
assert runpy.run_path(project / "bin/build-info")["input_digest"](project) == info["source_sha256"]
root = Path(tempfile.mkdtemp(prefix="cuckoding-r050p-", dir="/private/tmp"))
(root / ".fixture-v1").write_text("guest-battle-fixture-v1\n")
data = root / "data"
data.mkdir(mode=0o700)
log = project / ".ccoding" / ("r050p-battle-" + str(uuid.uuid4()) + ".log")
print(json.dumps({"fixture_root": str(root), "log": str(log), "build_id": info["build_id"]}), flush=True)
with (data / "shell.lock").open("xb") as lock, log.open("xb") as output:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    result = subprocess.run(["rtk", "proxy", "mix", "run", "--no-start", "test/support/guest_battle_fixture.exs"],
                            cwd=project, env={"HOME": os.environ["HOME"], "PATH": os.environ["PATH"], "LANG": "en_US.UTF-8", "TZ": "UTC",
                                 "MIX_ENV": "test", "CUCKODING_GUEST_FIXTURE_ROOT": str(root)},
                            stdout=output, stderr=subprocess.STDOUT, timeout=720)
    assert result.returncode == 0, (result.returncode, log)
evidence = json.loads((root / "evidence.json").read_bytes())
assert evidence["inference"] is False and evidence["state"] == "completed" and evidence["tasks"] == 2
assert evidence["source_and_index_preserved"] and evidence["responsive_during_checks"]
assert evidence["second_start_reused_image"] and evidence["paused_after_admission"]
assert 1 in evidence["review_rounds"]
checks = [row for stage in evidence["check_stages"] for row in stage["checks"]]
assert any(row["status"] == "failed" for row in checks)
assert all(row["vm_closed"] is True and row["native_state"] == 0 and row["cleanup_verified"] is True for row in checks)
for row in checks:
    private = data / "runtime-home/check-runs" / row["key"]
    receipt = json.loads((private / "receipt.json").read_bytes())
    assert receipt["check_sha256"] == row["check_sha256"] and receipt["request_id"] == row["request_id"]
    output = (private / "output.log").read_bytes()
    assert hashlib.sha256(output).hexdigest() == row["stdout_sha256"] and len(output) == row["stdout_bytes"]
old = json.loads((project / ".ccoding/r050p-old-bundle.json").read_bytes())
old_app = Path(old["root"]) / "Cuckoding.app"
assert old["build"]["schema"] == 18 and old_app.is_dir()
subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "--deep", str(old_app)], check=True, timeout=60)
database = data / "foundation.db"
before = hashlib.sha256(database.read_bytes()).hexdigest()
fence_log = root / "old-bundle-refusal.log"
with fence_log.open("xb") as output:
    result = subprocess.run([str(old_app / "Contents/MacOS/ccoding"), "--smoke-test"], cwd=root,
                            env={"HOME": str(root), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8",
                                 "CCODING_DATA_DIR": str(data), "CCODING_RELEASE_DIR": str(old_app / "Contents/Resources/release")},
                            stdout=output, stderr=subprocess.STDOUT, timeout=30)
assert result.returncode != 0
assert hashlib.sha256(database.read_bytes()).hexdigest() == before
with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as db:
    assert db.execute("SELECT count(*) FROM schema_migrations").fetchone()[0] == 19
    assert db.execute("SELECT count(*) FROM battles WHERE state='completed'").fetchone()[0] == 1
    assert db.execute("PRAGMA integrity_check").fetchone() == ("ok",)
evidence.update({"build": info, "helper_sha256": hashlib.sha256(helper.read_bytes()).hexdigest(),
                 "actual_vm_count": len(checks), "old_schema18_bundle_refused": True})
with (root / "verified.json").open("x") as output:
    json.dump(evidence, output, indent=2)
print(json.dumps({"state": evidence["state"], "actual_vm_count": len(checks), "forced_review_return": True,
                  "image_reuse_pause_stop": True, "coordinator_responsive": True, "old_bundle_refused": True,
                  "inference": False}), flush=True)
print("PASS: actual native VM checks through the source OTP Arena loop; real-provider/release acceptance remains separate.", flush=True)
