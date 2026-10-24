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
import stat
import subprocess
import sys
import tempfile
import uuid

os.umask(0o077)
assert sys.argv[1:] in ([], ["--task-checks"], ["--check-feedback"], ["--check-recovery"])
recovery = sys.argv[1:] == ["--check-recovery"]
feedback = recovery or sys.argv[1:] == ["--check-feedback"]
planned = bool(sys.argv[1:])
tag = "r060t" if recovery else "r050r" if feedback else "r050q" if planned else "r050p"
mode = "recovery" if recovery else "feedback" if feedback else "planned" if planned else "declared"
project = Path(__file__).resolve().parent.parent
app = project / "desktop/src-tauri/target/release/bundle/macos/Cuckoding.app"
helper = app / "Contents/MacOS/ccoding"
subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "--deep", str(app)], check=True, timeout=60)
info = json.loads(subprocess.check_output([str(helper), "--build-info"], timeout=5))
assert info["schema"] >= 19 and info["schema"] == len(list((project / "priv/repo/migrations").glob("*.exs")))
assert runpy.run_path(project / "bin/build-info")["input_digest"](project) == info["source_sha256"]
root = Path(tempfile.mkdtemp(prefix="cuckoding-" + tag + "-", dir="/private/tmp"))
(root / ".fixture-v1").write_text("guest-battle-fixture-v1\n")
data = root / "data"
data.mkdir(mode=0o700)
log = project / ".ccoding" / (tag + "-battle-" + str(uuid.uuid4()) + ".log")
print(json.dumps({"fixture_root": str(root), "log": str(log), "build_id": info["build_id"]}), flush=True)
with (data / "shell.lock").open("xb") as lock, log.open("xb") as output:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    result = subprocess.run(["rtk", "proxy", "mix", "run", "--no-start", "test/support/guest_battle_fixture.exs"],
                            cwd=project, env={"HOME": os.environ["HOME"], "PATH": os.environ["PATH"], "LANG": "en_US.UTF-8", "TZ": "UTC",
                                 "MIX_ENV": "test", "CUCKODING_GUEST_FIXTURE_ROOT": str(root),
                                 "CUCKODING_GUEST_FIXTURE_MODE": mode},
                            stdout=output, stderr=subprocess.STDOUT, timeout=720)
    assert result.returncode == 0, (result.returncode, log)
evidence = json.loads((root / "evidence.json").read_bytes())
assert evidence["inference"] is False and evidence["state"] == "completed" and evidence["tasks"] == 2
assert evidence["source_and_index_preserved"] and evidence["responsive_during_checks"]
assert evidence["second_start_reused_image"] and evidence["paused_after_admission"]
assert 1 in evidence["review_rounds"]
checks = [row for stage in evidence["check_stages"] for row in stage["checks"]]
assert len(checks) == (6 if planned else 7)
if planned:
    assert evidence["verification_mode"] == mode and evidence["configured_check_revision"] == 0
assert any(row["status"] == "failed" for row in checks)
if feedback:
    assert set(evidence["feedback_stages"]) >= {"speculator", "implementor", "secutor"}
    assert evidence["failure_feedback_verified"] is True
assert all(row["vm_closed"] is True and row["native_state"] == 0 and row["cleanup_verified"] is True for row in checks)
for row in checks:
    private = data / "runtime-home/check-runs" / row["key"]
    receipt = json.loads((private / "receipt.json").read_bytes())
    assert receipt["check_sha256"] == row["check_sha256"] and receipt["request_id"] == row["request_id"]
    output = (private / "output.log").read_bytes()
    assert hashlib.sha256(output).hexdigest() == row["stdout_sha256"] and len(output) == row["stdout_bytes"]
    if feedback and row["status"] == "failed":
        projection = receipt["failure_output"]
        excerpt = projection["excerpt"].encode("utf-8")
        assert len(excerpt) <= 4096 and projection["excerpt_bytes"] == len(excerpt)
        assert hashlib.sha256(excerpt).hexdigest() == projection["excerpt_sha256"]
        assert b"owned files" in excerpt
        with sqlite3.connect(f"file:{data / 'foundation.db'}?mode=ro", uri=True) as db:
            result = json.loads(db.execute("SELECT result FROM battle_attempts WHERE id=?", (row["request_id"],)).fetchone()[0])
            assert result["check_feedback"] == [{**projection, "check_id": row["id"],
                **{key: row[key] for key in ("request_id", "candidate_sha", "stdout_sha256", "stdout_bytes")}}]
            events = [json.loads(item[0]) for item in db.execute("SELECT data FROM events")]
            assert all('"excerpt"' not in json.dumps(event) for event in events)
old_tag = "r050r" if recovery else tag
old = json.loads((project / (".ccoding/" + old_tag + "-old-bundle.json")).read_bytes())
old_app = Path(old["root"]) / "Cuckoding.app"
assert old["build"]["schema"] == (20 if feedback else 19 if planned else 18) and old_app.is_dir()
subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "--deep", str(old_app)], check=True, timeout=60)
assert json.loads(subprocess.check_output([str(old_app / "Contents/MacOS/ccoding"), "--build-info"], timeout=5)) == old["build"]
database = data / "foundation.db"
before = hashlib.sha256(database.read_bytes()).hexdigest()
fence_log = root / "old-bundle-refusal.log"
crash = data / "erl_crash.dump"
assert not crash.exists()
with fence_log.open("xb") as output:
    result = subprocess.run([str(old_app / "Contents/MacOS/ccoding"), "--smoke-test"], cwd=root,
                            env={"HOME": str(root), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8",
                                 "CCODING_DATA_DIR": str(data), "CCODING_RELEASE_DIR": str(old_app / "Contents/Resources/release")},
                            stdout=output, stderr=subprocess.STDOUT, timeout=30)
assert result.returncode != 0
metadata = crash.lstat()
assert stat.S_ISREG(metadata.st_mode) and metadata.st_nlink == 1 and metadata.st_size <= 16 * 1024 * 1024
with crash.open("rb") as failure:
    message = failure.read(16 * 1024 * 1024 + 1)
assert len(message) <= 16 * 1024 * 1024 and b"database schema is newer than this application" in message
assert hashlib.sha256(database.read_bytes()).hexdigest() == before
with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as db:
    assert db.execute("SELECT count(*) FROM schema_migrations").fetchone()[0] == info["schema"]
    assert db.execute("SELECT count(*) FROM battles WHERE state='completed'").fetchone()[0] == 1
    if feedback:
        contexts = db.execute("SELECT context FROM battle_tasks WHERE battle_id=?", (evidence["battle_id"],)).fetchall()
        assert len(contexts)==2 and all(json.loads(row[0])["check_feedback"] == [] for row in contexts)
    assert db.execute("PRAGMA integrity_check").fetchone() == ("ok",)
evidence.update({"build": info, "helper_sha256": hashlib.sha256(helper.read_bytes()).hexdigest(),
                 "actual_vm_count": len(checks), "old_schema_bundle_refused": old["build"]["schema"]})
if recovery:
    evidence["retained_check_inspection"] = runpy.run_path(
        project / "test/support/guest_check_recovery_proof.py")["verify"](root, helper, checks)
with (root / "verified.json").open("x") as output:
    json.dump(evidence, output, indent=2)
print(json.dumps({"state": evidence["state"], "actual_vm_count": len(checks), "forced_review_return": True,
                  "image_reuse_pause_stop": True, "coordinator_responsive": True, "old_bundle_refused": True,
                  "inference": False}), flush=True)
print("PASS: actual native VM checks through the source OTP Arena loop; real-provider/release acceptance remains separate.", flush=True)
