#!/usr/bin/env python3
"""Bounded unpacked-release acceptance. Tokens stay in memory; no provider calls."""
import argparse
import http.cookiejar
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import queue
import re
import shutil
import signal
import socket
import sqlite3
import subprocess
import tarfile
import tempfile
import threading
import time
import urllib.parse
import urllib.request


class Page(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.csrf = None
        self.assets = []
        self.feed(text)

    def handle_starttag(self, tag, attributes):
        attributes = dict(attributes)
        if tag == "input" and attributes.get("name") == "_csrf_token":
            self.csrf = attributes.get("value")
        asset = attributes.get("src") if tag == "script" else attributes.get("href")
        if asset and asset.startswith("/assets/"):
            self.assets.append(asset)


def main(archive):
    archive = archive.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="boss-release-smoke-") as temporary:
        root = Path(temporary).resolve()
        release = root / "release"
        release.mkdir()
        with tarfile.open(archive) as package:
            package.extractall(release, filter="data")
        executable = release / "bin/boss"
        assert executable.is_file(), "Release launcher missing"
        assert list(release.glob("erts-*/bin/beam.smp")), "Bundled ERTS missing"
        assert list(release.glob("lib/boss-*/priv/native/boss_guardian")), "Guardian missing"
        assert (release / "BUILD_INFO").is_file(), "Build provenance missing"
        assert (release / "LICENSES/OpenSSL-LICENSE.txt").is_file(), "OpenSSL notice missing"
        binary = root / "bin"
        binary.mkdir()
        # Only required system helpers and Git are visible to the child runtime.
        for name in ["sh", "dirname", "basename", "readlink", "cut", "sed", "cat", "dd",
                     "od", "awk", "grep", "mkdir", "uname", "getconf", "git"]:
            found = shutil.which(name)
            assert found, f"Required system utility missing: {name}"
            (binary / name).symlink_to(found)
        for name in ["elixir", "erl", "mix", "node", "npm", "cc", "clang", "codex", "claude"]:
            assert shutil.which(name, path=str(binary)) is None
        cwd = root / "unrelated-cwd"
        cwd.mkdir()
        home = root / "home"
        home.mkdir()
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        base = f"http://127.0.0.1:{port}"
        environment = {key: value for key, value in os.environ.items()
                       if not key.startswith(("BOSS_", "ERL_", "ELIXIR_", "MIX_", "RELEASE_", "DYLD_", "GIT_"))}
        environment.pop("PHX_SERVER", None)
        environment.update(PATH=str(binary), HOME=str(home), PORT=str(port),
                           BOSS_DATA_DIR=str(root / "data"), GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        crash = subprocess.run([executable, "eval", ':erlang.halt(~c"BOSS_SMOKE_CRASH_DUMP")'],
                               cwd=cwd, env=environment, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=10)
        assert crash.returncode != 0, "Deliberate crash probe unexpectedly succeeded"
        assert not (cwd / "erl_crash.dump").exists(), "Release wrote a BEAM memory dump"
        process = None

        def stop():
            nonlocal process
            if process is not None:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=20)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)
                        raise AssertionError("Release did not stop gracefully")
                assert process.returncode == 0, "Release exited unsuccessfully"
                process.stdout.close()
                process = None

        def start():
            nonlocal process
            tokens = queue.Queue(maxsize=1)
            process = subprocess.Popen([executable, "start"], cwd=cwd, env=environment,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, start_new_session=True)

            def read_terminal():
                pending = False
                for line in process.stdout:
                    if pending and re.fullmatch(r"[A-Za-z0-9_-]{43}", line.strip()):
                        tokens.put_nowait(line.strip())
                        pending = False
                    elif "one-use token (10 minutes):" in line:
                        pending = True

            threading.Thread(target=read_terminal, daemon=True).start()
            try:
                token = tokens.get(timeout=30)
            except queue.Empty:
                raise AssertionError("Release did not announce its local token") from None
            deadline = time.monotonic() + 10
            opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
            while True:
                try:
                    text = opener.open(base + "/unlock", timeout=2).read().decode()
                    break
                except OSError:
                    assert process.poll() is None, "Release stopped before HTTP readiness"
                    if time.monotonic() > deadline:
                        raise AssertionError("Release HTTP readiness timed out") from None
                    time.sleep(0.05)
            page = Page(text)
            assert page.csrf, "Unlock form CSRF missing"
            request = urllib.request.Request(base + "/unlock", method="POST",
                data=urllib.parse.urlencode({"_csrf_token": page.csrf, "token": token}).encode(),
                headers={"Origin": base, "Referer": base + "/unlock"})
            token = None
            response = opener.open(request, timeout=10)
            assert response.geturl() == base + "/", "Token exchange did not authenticate"
            text = response.read().decode()
            page = Page(text)
            assert page.assets, "Digested assets missing from HTML"
            for asset in page.assets:
                assert opener.open(base + asset, timeout=10).status == 200
            return text

        try:
            assert "Projects" in start()
            stop()
            source = root / "source"
            source.mkdir()
            (source / "specs").mkdir()
            (source / "specs/smoke.md").write_text("# Release smoke task")
            git = str(binary / "git")
            for args in [["init", "-b", "main"], ["add", "."],
                         ["-c", "user.name=Smoke", "-c", "user.email=smoke@example.invalid",
                          "-c", "commit.gpgSign=false", "commit", "-m", "base"]]:
                subprocess.run([git, *args], cwd=source, env=environment, check=True,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
            expression = ("{:ok, _} = Application.ensure_all_started(:boss); "
                          "%{outcome: :exited, exit_kind: :exit, exit_code: 0, "
                          "eof: %{stdout: true, stderr: true}, cleanup: :group_empty} = "
                          "Boss.Agents.Process.run(System.find_executable(\"git\"), [\"--version\"], "
                          f"cd: {json.dumps(str(source))}, timeout_ms: 5000, output_limit: 8192); "
                          "{:ok, project} = Boss.Projects.create_project(%{"
                          f"root_path: {json.dumps(str(source))}, specs_path: \"specs\", "
                          "base_branch: \"main\", name: \"Release smoke project\"}); "
                          "{:ok, _} = Boss.Projects.record_spec(project.id, %{"
                          "relative_path: \"smoke.md\", title: \"Release smoke task\", "
                          "original_text: \"# Release smoke task\"}); "
                          "IO.puts(\"BOSS_SMOKE_STATE_SAVED\")")
            seeded = subprocess.run([executable, "eval", expression], cwd=cwd, env=environment,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30)
            assert seeded.returncode == 0 and "BOSS_SMOKE_STATE_SAVED" in seeded.stdout, "State seed failed"
            assert "Release smoke project" in start(), "Project did not survive restart"
            stop()
            with sqlite3.connect(root / "data/boss.db") as database:
                assert database.execute("PRAGMA integrity_check").fetchone() == ("ok",)
                assert database.execute("PRAGMA foreign_key_check").fetchall() == []
                assert database.execute("SELECT count(*) FROM tasks").fetchone() == (1,)
            print("Release smoke passed: unpack, bundled runtime/guardian, login/assets, persisted state, restart, graceful stop")
        finally:
            if process is not None:
                try:
                    stop()
                except AssertionError:
                    if process is not None and process.poll() is None:
                        process.kill()
                        process.wait(timeout=5)
                    raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    main(args.archive)
