#!/usr/bin/env python3
"""Build pinned macOS arm64 OTP/static OpenSSL in an exclusively new directory."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import time

SOURCES = {
    "otp": {
        "version": "28.5.0.8", "directory": "otp_src_28.5.0.8",
        "url": "https://github.com/erlang/otp/releases/download/OTP-28.5.0.8/otp_src_28.5.0.8.tar.gz",
        "sha256": "8a696e15bcbe5d57197b1f4c03c92d415f9fd9af70f9222a05911c8a5463cba6",
        "bytes": 105458074, "commit": "882bc060aca3f9491ba6345da56c5076793d31e2",
    },
    "openssl": {
        "version": "3.5.9", "directory": "openssl-3.5.9",
        "url": "https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz",
        "sha256": "603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a",
        "bytes": 53279637, "commit": "45e844fa2a14ec92d146bd8f5778ac130b6625fb",
    },
}
VENDOR_NOTICES = (
    "asmjit/LICENSE.md", "pcre/LICENCE", "zstd/LICENSE",
    "ryu/LICENSE-Apache2", "ryu/LICENSE-Boost",
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def unpack(archive, source, destination):
    require(archive.stat().st_size == source["bytes"] and digest(archive) == source["sha256"],
            "Source archive size/SHA256 mismatch: " + archive.name)
    destination.mkdir()
    with tarfile.open(archive) as package:
        package.extractall(destination, filter="data")
    result = destination / source["directory"]
    require(result.is_dir() and not result.is_symlink(), "Unexpected upstream source root")
    return result


def run(command, cwd, env, log, timeout=1800):
    with log.open("ab") as output:
        output.write(("\n$ " + repr(command) + "\n").encode())
        output.flush()
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            status = process.wait(timeout=timeout)
            if status:
                raise subprocess.CalledProcessError(status, command)
        except BaseException:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)
            raise


def main(output, jobs):
    require(sys.platform == "darwin" and platform.machine() == "arm64", "Requires native macOS arm64")
    require(1 <= jobs <= 8, "Jobs must be between 1 and 8")
    output = output.resolve()
    output.mkdir(mode=0o700)  # Never overwrite or remove a pre-existing root.
    started = time.monotonic()
    log = output / "build.log"
    downloads = output / "sources"
    downloads.mkdir()
    scratch = output / "build"
    scratch.mkdir()
    env = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(output),
           "TMPDIR": str(scratch), "LANG": "C", "LC_ALL": "C",
           "CC": "/usr/bin/clang", "CXX": "/usr/bin/clang++",
           "AR": "/usr/bin/ar", "RANLIB": "/usr/bin/ranlib",
           "OPENSSL_CONF": "/dev/null", "ERL_CRASH_DUMP": "/dev/null"}
    roots = {}
    for name, source in SOURCES.items():
        print("Fetching verified " + name + " " + source["version"], flush=True)
        archive = downloads / (source["directory"] + ".tar.gz")
        run(["/usr/bin/curl", "--fail", "--location", "--silent", "--show-error",
             "--proto", "=https", "--proto-redir", "=https", "--max-time", "300",
             "--max-filesize", str(source["bytes"]), "--output", str(archive), source["url"]],
            output, env, log, timeout=310)
        roots[name] = unpack(archive, source, scratch / name)
    openssl = output / "openssl"
    otp = output / "otp"
    ssl_args = ["darwin64-arm64-cc", "no-shared", "no-module", "no-tests", "--libdir=lib",
                "--prefix=" + str(openssl), "--openssldir=" + str(openssl / "ssl")]
    otp_args = ["--prefix=" + str(otp), "--with-ssl=" + str(openssl),
                "--disable-dynamic-ssl-lib", "--with-ssl-rpath=no",
                "--without-wx", "--without-javac", "--without-odbc"]
    print("Building static OpenSSL (jobs=" + str(jobs) + ")", flush=True)
    run(["/usr/bin/perl", "Configure", *ssl_args], roots["openssl"], env, log)
    run(["/usr/bin/make", "-j" + str(jobs)], roots["openssl"], env, log)
    run(["/usr/bin/make", "install_sw"], roots["openssl"], env, log)
    require((openssl / "lib/libcrypto.a").is_file(), "Static OpenSSL library missing")
    require(not list(openssl.rglob("*.dylib")) and not list(openssl.rglob("*.so")),
            "Unexpected dynamic OpenSSL output")
    env["PATH"] = str(openssl / "bin") + ":" + env["PATH"]
    print("Building OTP (jobs=" + str(jobs) + ")", flush=True)
    run(["./configure", *otp_args], roots["otp"], env, log)
    run(["/usr/bin/make", "-j" + str(jobs)], roots["otp"], env, log)
    run(["/usr/bin/make", "install"], roots["otp"], env, log)
    expression = r'''
      {ok, _} = application:ensure_all_started(crypto),
      Root = code:root_dir(),
      {ok, Version} = file:read_file(filename:join([Root, "releases", erlang:system_info(otp_release), "OTP_VERSION"])),
      [{_, _, OpenSSL}] = crypto:info_lib(),
      32 = byte_size(crypto:strong_rand_bytes(32)),
      32 = byte_size(crypto:hash(sha256, <<"BOSS release runtime">>)),
      io:format("OTP=~s~nERTS=~s~nOPENSSL=~s~nCRYPTO=~s~n", [string:trim(Version), erlang:system_info(version), OpenSSL, filename:join(code:priv_dir(crypto), "lib/crypto.so")]),
      halt().
    '''
    probe = output / "runtime-check.txt"
    run([str(otp / "bin/erl"), "-noshell", "-eval", expression], output, env, probe, timeout=30)
    values = dict(re.findall(r"^(OTP|ERTS|OPENSSL|CRYPTO)=(.+)$", probe.read_text(), re.MULTILINE))
    require(values.get("OTP") == SOURCES["otp"]["version"] and
            values.get("OPENSSL", "").startswith("OpenSSL " + SOURCES["openssl"]["version"] + " "),
            "Actual OTP/OpenSSL version mismatch")
    crypto = Path(values["CRYPTO"])
    require(crypto.is_relative_to(otp) and crypto.is_file(), "Crypto NIF escaped installed runtime")
    linked = subprocess.run(["/usr/bin/otool", "-L", str(crypto)], check=True,
                            capture_output=True, text=True, timeout=30).stdout
    dependencies = re.findall(r"^\s+(.+) \(compatibility version", linked, re.MULTILINE)
    require(dependencies and all(path.startswith(("/usr/lib/", "/System/Library/")) for path in dependencies),
            "Crypto NIF has a non-system dynamic dependency")
    licenses = output / "licenses"
    licenses.mkdir()
    license_hashes = {}
    for name, relative in (("otp", "LICENSE.txt"), ("openssl", "LICENSE.txt")):
        destination = licenses / ("Erlang-LICENSE.txt" if name == "otp" else "OpenSSL-LICENSE.txt")
        shutil.copyfile(roots[name] / relative, destination)
        license_hashes[name] = digest(destination)
    notices = {}
    for relative in VENDOR_NOTICES:
        key = "OTP/" + relative
        destination = output / "NOTICES" / key
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(roots["otp"] / "erts/emulator" / relative, destination)
        notices[key] = digest(destination)
    for key, relative, end, expected in (
        ("OTP/tcl/erl_posix_str-LICENSE.txt", "beam/erl_posix_str.c", b"*/", "2b7bde88a5a2b0543d299d69d0f40e8212cd7606d12c0180346e3a72b25cf460"),
        ("OTP/ryu/to_chars-LICENSE.txt", "ryu/to_chars.h", b"enum chars_format", "88179226df8e99eb708ced24b28f3a18f5cde5edbd0e315655308cb9575ad0fc"),
    ):
        raw = (roots["otp"] / "erts/emulator" / relative).read_bytes()
        require(end in raw, "Upstream notice boundary missing")
        notice = raw.split(end, 1)[0] + (b"*/\n" if end == b"*/" else b"")
        require(hashlib.sha256(notice).hexdigest() == expected, "Pinned source notice mismatch")
        destination = output / "NOTICES" / key
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(notice)
        notices[key] = digest(destination)
    vendor_components = {}
    for name in ("asmjit", "pcre", "zstd", "ryu", "openssl"):
        vendor = roots["otp"] / "erts/emulator" / name / "vendor.info"
        if vendor.is_file():
            entries = json.loads(re.sub(r"^//.*$", "", vendor.read_text(), flags=re.MULTILINE))
            entry = entries[0]
            key = "openssl_md5" if name == "openssl" else name
            vendor_components[key] = {"version": entry.get("versionInfo"), "source_commit": entry.get("sha"),
                                      "vendor_info_sha256": digest(vendor)}
    require(vendor_components["openssl_md5"]["version"] == "3.6.1", "Unexpected ERTS MD5 vendor")
    vendor_components["openssl_md5"]["scope"] = "ERTS builtin MD5 only"
    generated = {}
    for config in (roots["otp"] / "erts").rglob("config.h"):
        for key, value in re.findall(r"^#define (ERTS_USE_[A-Z0-9_]+) (\S+)", config.read_text(errors="replace"), re.MULTILINE):
            if any(part in key for part in ("RYU", "ZSTD", "ZLIB", "MD5", "OPENSSL", "ERRNO")):
                generated[key] = value
    beam = otp / "lib/erlang" / ("erts-" + values["ERTS"]) / "bin/beam.smp"
    beam_links = subprocess.run(["/usr/bin/otool", "-L", str(beam)], check=True,
                                capture_output=True, text=True, timeout=30).stdout
    require("/usr/lib/libz.1.dylib" in beam_links, "Expected system zlib linkage")
    manifest = {"schema_version": 1, "platform": "darwin", "architecture": "arm64",
                "otp_version": values["OTP"], "openssl_version": SOURCES["openssl"]["version"],
                "erts_version": values["ERTS"], "runtime_openssl": values["OPENSSL"],
                "crypto_sha256": digest(crypto), "crypto_linkage": "static",
                "sources": SOURCES, "licenses": license_hashes, "notices": notices,
                "generated_erts_flags": generated, "system_zlib": "/usr/lib/libz.1.dylib",
                "otp_vendor_components": vendor_components,
                "configure": {"openssl": [arg.replace(str(output), "$" + "{OUTPUT}") for arg in ssl_args],
                              "otp": [arg.replace(str(output), "$" + "{OUTPUT}") for arg in otp_args]},
                "elapsed_seconds": round(time.monotonic() - started, 3)}
    shutil.rmtree(scratch)  # This source/build directory was exclusively created above.
    pending = output / ".runtime-info.pending"
    pending.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    pending.rename(output / "RUNTIME_INFO.json")
    print("Pinned runtime complete: " + str(otp / "bin/erl"), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="Exclusively new root; failed roots are retained")
    parser.add_argument("--jobs", type=int, default=min(4, os.cpu_count() or 1))
    args = parser.parse_args()
    try:
        main(args.output, args.jobs)
    except (OSError, ValueError, tarfile.TarError, subprocess.SubprocessError) as error:
        parser.exit(1, "Runtime build failed: " + str(error) + "\nOutput retained; inspect build.log.\n")
