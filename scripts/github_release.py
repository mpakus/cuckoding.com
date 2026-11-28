"""Promote the exact successful main-branch macOS build to its matching Git tag."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import time


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def gh(*args):
    return subprocess.check_output(["gh", *map(str, args)], text=True).strip()


def api(path):
    return json.loads(gh("api", f"repos/{os.environ['GITHUB_REPOSITORY']}/{path}"))


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def mode_for(tag, archive_tag):
    require(re.fullmatch(r"v\d+\.\d+\.\d+(?:-rc\.\d+)?", tag), "Unsupported release tag")
    if tag == archive_tag:
        require("-rc." in tag, "Archive-only publication requires an RC tag")
        return "archive"
    return "signed"


def release_notes(tag, changelog, mode, sha):
    header = re.search(rf"^## {re.escape(tag[1:])}(?: — [^\n]+)?\n", changelog, re.M)
    require(header, "Tag version missing from CHANGELOG.md")
    section = re.split(r"^## ", changelog[header.end():], maxsplit=1, flags=re.M)[0].strip()
    require(section, "Empty changelog section")
    distribution = {
        "archive": "Download the unsigned macOS arm64 tar.gz and SHA256SUMS. This preview is for Apple Silicon Macs.",
        "signed": "Download the Developer ID signed and Apple-notarized macOS arm64 DMG and SHA256SUMS.",
    }
    return f"{section}\n\n{distribution[mode]}\n\nSource commit: `{sha}`\n"


def verify_archive(directory, tag, sha):
    archive = directory / f"boss-{tag[1:]}.tar.gz"
    expected = f"{sha256(archive)}  _build/prod/{archive.name}"
    require((directory / "SHA256SUMS").read_text().splitlines() == [expected],
            "Candidate checksum differs from the tested archive")
    with tarfile.open(archive, "r:gz") as package:
        members = [m for m in package if m.name.removeprefix("./") == "BUILD_INFO"]
        require(len(members) == 1 and members[0].isfile() and members[0].size <= 32768,
                "Missing or ambiguous build provenance")
        lines = package.extractfile(members[0]).read().decode().splitlines()
    for key, value in [("BOSS ", tag[1:]), ("Source commit: ", sha),
                       ("Source local changes: ", "false"), ("Architecture: ", "arm64")]:
        require([line for line in lines if line.startswith(key)] == [key + value],
                f"Provenance mismatch for {key.strip()}")
    return archive


def candidate_run(sha):
    endpoint = f"actions/workflows/release-candidate.yml/runs?branch=main&event=push&head_sha={sha}&per_page=1"
    deadline = time.monotonic() + 65 * 60
    while time.monotonic() < deadline:
        runs = api(endpoint)["workflow_runs"]
        if runs:
            run = runs[0]
            require((run["head_sha"], run["head_branch"], run["event"], run["head_repository"]["full_name"])
                    == (sha, "main", "push", os.environ["GITHUB_REPOSITORY"]), "Unexpected candidate source")
            if run["status"] == "completed":
                require(run["conclusion"] == "success", f"Candidate failed: {run['html_url']}")
                return str(run["id"])
        time.sleep(20)
    raise SystemExit("No successful candidate for this exact main-branch commit before the deadline")


def release(tag):
    # Include drafts, including a previous interrupted publication.
    pages = json.loads(gh("api", "--paginate", "--slurp",
                          f"repos/{os.environ['GITHUB_REPOSITORY']}/releases?per_page=100"))
    matches = [item for page in pages for item in page if item["tag_name"] == tag]
    require(len(matches) <= 1, "Multiple releases found for this tag")
    return matches[0] if matches else None


def output(key, value):
    with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
        print(f"{key}={value}", file=stream)


def check_tag(tag, sha):
    require(api(f"commits/{tag}")["sha"] == sha, "Remote tag moved from the checked-out commit")


def metadata(tag, sha):
    mode = mode_for(tag, os.environ.get("BOSS_ARCHIVE_ONLY_TAG", ""))
    versions = re.findall(r'^\s+version: "([^"]+)",$', Path("mix.exs").read_text(), re.M)
    require(versions == [tag[1:]], "Tag and mix.exs version differ")
    return mode, release_notes(tag, Path("CHANGELOG.md").read_text(), mode, sha)


def selected_metadata(tag, sha, current):
    mode, notes = metadata(tag, sha)
    if current and not current["draft"]:
        # A published preview remains verifiable after its one-tag opt-in is removed.
        mode = "archive" if any(a["name"].endswith(".tar.gz") for a in current["assets"]) else "signed"
        require(mode != "archive" or "-rc." in tag, "Stable archive-only release")
        notes = release_notes(tag, Path("CHANGELOG.md").read_text(), mode, sha)
    return mode, notes


def prepare(tag, sha, root):
    check_tag(tag, sha)
    archive = verify_archive(root / "candidate", tag, sha)
    existing = release(tag)
    mode, notes = selected_metadata(tag, sha, existing)
    dist = root / "distribution"
    dist.mkdir()
    filename = f"boss-{tag[1:]}-macos-arm64"
    if mode == "archive":
        shutil.copyfile(archive, dist / (filename + ".tar.gz"))
    notes_path = root / "release-notes.md"
    notes_path.write_text(notes)
    if existing is None:
        flags = ["--prerelease", "--latest=false"] if "-rc." in tag else []
        gh("release", "create", tag, "--verify-tag", "--target", sha, "--draft",
           "--title", f"BOSS {tag[1:]}", "--notes-file", notes_path, *flags)
        existing = release(tag)
    elif (existing["draft"] and not existing["assets"] and mode == "archive" and
          existing["body"].strip() == release_notes(tag, Path("CHANGELOG.md").read_text(), "signed", sha).strip()):
        gh("release", "edit", tag, "--notes-file", notes_path)
        existing = release(tag)
    require(existing and existing["body"].strip() == notes.strip() and
            existing["prerelease"] == ("-rc." in tag), "Existing release notes, mode or prerelease flag differ")
    output("mode", mode)
    output("draft", str(existing["draft"]).lower())
    if mode == "signed" and existing["draft"]:
        require(not existing["assets"], "Prior signing intent or assets exist. Reconcile that submission before resuming.")


def asset_digests(release_info):
    return {a["name"]: a["digest"] for a in release_info["assets"]}


def check_signed(directory, image, archive, tag, sha):
    report = json.loads((directory / "NOTARIZATION.json").read_text())
    intent = json.loads((directory / "NOTARY_REQUEST.json").read_text())
    submission = json.loads((directory / "NOTARY_SUBMISSION.json").read_text())
    require(submission["submission_id"] == report["submission_id"] and
            submission["submitted_sha256"] == intent["submitted_sha256"], "Submission receipt mismatch")
    require(intent["tag"] == tag and intent["commit"] == sha and
            intent["source_archive_sha256"] == sha256(archive), "Notarization request belongs to another build")
    require(report["status"] == "Accepted" and report["staple_validated"] is True
            and report["gatekeeper_assessed"] is True and report["submission_id"]
            and report["stapled_sha256"] == sha256(image)
            and report["submitted_sha256"] == intent["submitted_sha256"], "Incomplete notarization evidence")


def finish(tag, sha, root):
    check_tag(tag, sha)
    current = release(tag)
    mode, notes = selected_metadata(tag, sha, current)
    dist = root / "distribution"
    filename = f"boss-{tag[1:]}-macos-arm64"
    archive = verify_archive(root / "candidate", tag, sha)
    require(current and current["body"].strip() == notes.strip() and
            current["prerelease"] == ("-rc." in tag), "Release draft changed during promotion")
    desired = {filename + ".tar.gz", "SHA256SUMS"} if mode == "archive" else {
        filename + ".dmg", "NOTARY_REQUEST.json", "NOTARY_SUBMISSION.json", "NOTARIZATION.json", "SHA256SUMS"}
    if mode == "signed" and current["draft"]:
        folder = root / "signed"
        check_signed(folder, folder / "boss.dmg", archive, tag, sha)
        shutil.copyfile(folder / "boss.dmg", dist / (filename + ".dmg"))
        for name in ["NOTARY_REQUEST.json", "NOTARY_SUBMISSION.json", "NOTARIZATION.json"]:
            shutil.copyfile(folder / name, dist / name)
    if current["draft"]:
        checks = "".join(f"{sha256(dist / name)}  {name}\n" for name in sorted(desired - {"SHA256SUMS"}))
        (dist / "SHA256SUMS").write_text(checks)
        expected = {name: "sha256:" + sha256(dist / name) for name in desired}
        existing = asset_digests(current)
        if mode == "signed":
            submitted = json.loads((dist / "NOTARY_REQUEST.json").read_text())["submitted_sha256"]
            require(existing.pop("boss-submitted.dmg", None) == "sha256:" + submitted,
                    "Saved submission input differs")
        require(all(expected.get(name) == digest for name, digest in existing.items()),
                "Existing draft asset differs; refusing to overwrite it")
        for name in sorted(desired - existing.keys()):
            gh("release", "upload", tag, dist / name)
        if mode == "signed":
            require(asset_digests(release(tag)) == {**expected, "boss-submitted.dmg": "sha256:" + submitted},
                    "Final signed draft assets do not match")
            gh("release", "delete-asset", tag, "boss-submitted.dmg", "--yes")
        require(asset_digests(release(tag)) == expected, "Incomplete or mismatched draft assets")
        check_tag(tag, sha)
        gh("release", "edit", tag, "--draft=false", "--latest=false" if "-rc." in tag else "--latest")
    published = release(tag)
    digests = asset_digests(published)
    require(not published["draft"] and published["prerelease"] == ("-rc." in tag)
            and set(digests) == desired, "Published release differs")
    downloaded = root / "published"
    gh("release", "download", tag, "--dir", downloaded)
    require(all(digests[name] == "sha256:" + sha256(downloaded / name) for name in desired),
            "Downloaded release assets differ from GitHub digests")
    checks = "".join(f"{sha256(downloaded / name)}  {name}\n" for name in sorted(desired - {"SHA256SUMS"}))
    require((downloaded / "SHA256SUMS").read_text() == checks, "Published SHA256SUMS differs")
    if mode == "archive":
        require(sha256(downloaded / (filename + ".tar.gz")) == sha256(archive),
                "Published archive differs from the tested candidate")
    else:
        check_signed(downloaded, downloaded / (filename + ".dmg"), archive, tag, sha)
    print(published["html_url"])


if __name__ == "__main__":
    tag = os.environ["GITHUB_REF_NAME"]
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    require(re.fullmatch(r"[a-f0-9]{40}", sha), "Invalid checkout")
    require(os.environ["GITHUB_REF_TYPE"] == "tag", "Select an existing release tag")
    metadata(tag, sha)
    root = Path(os.environ["RUNNER_TEMP"])
    if sys.argv[1:] == ["candidate"]:
        check_tag(tag, sha)
        output("run", candidate_run(sha))
        output("sha", sha)
    elif sys.argv[1:] == ["prepare"]:
        prepare(tag, sha, root)
    elif sys.argv[1:] == ["finish"]:
        finish(tag, sha, root)
    else:
        raise SystemExit("Expected candidate, prepare or finish")
