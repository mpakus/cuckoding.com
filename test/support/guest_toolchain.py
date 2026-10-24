"""Pinned offline toolchains and synthetic Git candidates; no production execution hook."""
from pathlib import Path, PurePosixPath
import hashlib
import json
import os
import stat
import subprocess
import tarfile
import uuid
import zipfile

MODES = ('check_npm_pass', 'check_npm_fail', 'check_mix_pass', 'check_mix_fail', 'check_forgery',
         'check_source_mutation', 'check_output_boundary', 'check_output_limit', 'check_cancel', 'check_owner_loss')

INIT = b'''#!/bin/sh
set -e
B=/bin/busybox
trap 'echo CHECK_SETUP_FAILED; /bin/busybox poweroff -f' EXIT
$B mount -t devtmpfs devtmpfs /dev
$B mount -t proc proc /proc
$B mount -t sysfs sysfs /sys
$B mount -t cgroup2 none /sys/fs/cgroup
$B chmod 600 /dev/hvc0 /dev/console
echo '+pids +memory +cpu' > /sys/fs/cgroup/cgroup.subtree_control
$B mkdir /sys/fs/cgroup/work /run/check /tmp/home
$B chmod 1777 /tmp
$B chown 1000:1000 /tmp/home
C=/sys/fs/cgroup/work
echo 128 > "$C/pids.max"
echo 536870912 > "$C/memory.max"
echo 0 > "$C/memory.swap.max"
echo 1 > "$C/memory.oom.group"
echo '100000 100000' > "$C/cpu.max"
export PATH=/opt/elixir/bin:/usr/bin:/bin HOME=/tmp/home LANG=C.UTF-8
export ERL_FLAGS='+S 2:2 +SDcpu 1 +SDio 1 +A 1' HEX_OFFLINE=1 MIX_ENV=test
CASE=''
for arg in $($B cat /proc/cmdline); do case "$arg" in cc_check=*) CASE=${arg#cc_check=};; esac; done
case "$CASE" in check_npm_pass|check_npm_fail|check_forgery|check_source_mutation|check_output_boundary|check_output_limit|check_cancel|check_owner_loss) COMMAND='npm test --offline'
    [ "$(/usr/bin/node --version)" = 'v24.22.1' ]; [ "$(/usr/bin/npm --version)" = '11.12.1' ];;
check_mix_pass|check_mix_fail) COMMAND='mix test'
    [ "$(/opt/elixir/bin/elixir -e 'IO.write(System.version() <> "|" <> String.trim(File.read!(Path.join([:code.root_dir(), "releases", "28", "OTP_VERSION"]))))')" = '1.20.3|28.5.0.8' ];;
*) exit 1;; esac
export CASE
echo CHECK_RUNNING
/bin/sh /launch > /tmp/check.stdout 2>&1 < /dev/null &
i=0
READY=false
while [ ! -f /run/check/exit ] && [ "$i" -lt 300 ]; do
    if [ "$READY" = false ] && $B grep -q ACTUAL_NODE_READY /tmp/check.stdout; then echo CHECK_READY; READY=true; fi
    $B sleep 0.1; i=$((i+1))
done
EXIT_CODE=124
if [ -f /run/check/exit ]; then read EXIT_CODE < /run/check/exit; fi
echo 1 > "$C/cgroup.kill"
i=0
while ! $B grep -q '^populated 0$' "$C/cgroup.events" && [ "$i" -lt 20 ]; do $B sleep 0.1; i=$((i+1)); done
$B grep -q '^populated 0$' "$C/cgroup.events"
read REQUEST CANDIDATE IMAGE < /requests/$CASE
UNCHANGED=true
# No worker remains. Refuse links/devices before privileged source hashing.
while read HASH NAME; do
    P=/work/$CASE/$NAME
    D=$P
    while [ "$D" != /work ]; do
        [ ! -L "$D" ] || UNCHANGED=false
        D=${D%/*}
    done
    [ -f "$P" ] && [ "$($B stat -c %a "$P")" = 644 ] || UNCHANGED=false
done < /manifests/$CASE
if [ "$UNCHANGED" = true ]; then
    (cd /work/$CASE && $B sha256sum -c /manifests/$CASE >/dev/null 2>&1) || UNCHANGED=false
fi
set -- $($B sha256sum /tmp/check.stdout); HASH=$1
BYTES=$($B wc -c < /tmp/check.stdout)
[ "$BYTES" -le 65536 ] || exit 1
OUTPUT=$($B base64 -w 0 /tmp/check.stdout)
printf 'CHECK_RESULT {"request_id":"%s","candidate_sha":"%s","toolchain_sha256":"%s","command":"%s","exit_code":%s,"stdout_sha256":"%s","stdout_bytes":%s,"source_unchanged":%s,"stdout_base64":"%s"}\n' "$REQUEST" "$CANDIDATE" "$IMAGE" "$COMMAND" "$EXIT_CODE" "$HASH" "$BYTES" "$UNCHANGED" "$OUTPUT"
trap - EXIT
$B poweroff -f
'''

LAUNCH = b'''#!/bin/sh
set -e
B=/bin/busybox
echo $$ > /sys/fs/cgroup/work/cgroup.procs
ulimit -c 0
ulimit -n 128
# BEAM JIT uses memory-backed files; bound output separately from artifact size.
ulimit -f 131072
set +e
$B su -s /bin/sh -c 'exec /bin/busybox setpriv --nnp /bin/sh /worker' worker
result=$?
echo "$result" > /run/check/exit.tmp
$B mv /run/check/exit.tmp /run/check/exit
'''

WORKER = b'''#!/bin/sh
set -e
B=/bin/busybox
[ "$($B id -u)" = 1000 ] && [ "$($B id -g)" = 1000 ]
$B grep -q '^NoNewPrivs:[[:space:]]*1$' /proc/self/status
$B grep -q '^CapEff:[[:space:]]*0000000000000000$' /proc/self/status
$B grep -q '^0::/work$' /proc/self/cgroup
export PATH=/opt/elixir/bin:/usr/bin:/bin HOME=/tmp/home
export ERL_FLAGS='+S 2:2 +SDcpu 1 +SDio 1 +A 1' HEX_OFFLINE=1 MIX_ENV=test
export NPM_CONFIG_CACHE=/tmp/home/.npm NPM_CONFIG_AUDIT=false NPM_CONFIG_FUND=false
for arg in $(/bin/busybox cat /proc/cmdline); do case "$arg" in cc_check=*) CASE=${arg#cc_check=};; esac; done
cd /work/$CASE || exit 2
case "$CASE" in check_npm_pass|check_npm_fail|check_forgery|check_source_mutation|check_output_boundary|check_output_limit|check_cancel|check_owner_loss) exec /usr/bin/npm test --offline;;
check_mix_pass|check_mix_fail) exec /opt/elixir/bin/mix test;; *) exit 2;; esac
'''


def prepare(root, environment, entries):
    source = Path(__file__).parent
    manifest = json.loads((source / 'guest-toolchain-inputs.json').read_text())
    image = hashlib.sha256(json.dumps(manifest, sort_keys=True).encode() + INIT + LAUNCH + WORKER).hexdigest()
    tree = {name: (mode, data) for name, mode, data in entries if name not in ('init', 'TRAILER!!!')}

    def add(name, mode, data):
        name = name.removeprefix('./').rstrip('/')
        path = PurePosixPath(name)
        assert name and not path.is_absolute() and '..' not in path.parts
        assert len(name) <= 1024 and len(data) <= 64 * 1024**2
        if name in tree:
            assert tree[name] == (mode, data), ('toolchain_path_collision', name)
        tree[name] = (mode, data)

    for package in manifest:
        dest = root / package['filename']
        subprocess.run(['/usr/bin/curl', '--disable', '--fail', '--location', '--proto', '=https',
                        '--connect-timeout', '10', '--max-time', '90', '--max-filesize', '134217728',
                        '--silent', '--show-error', '--output', str(dest), package['url']],
                       env=environment, check=True, timeout=95)
        assert dest.stat().st_size == package['bytes']
        assert hashlib.sha256(dest.read_bytes()).hexdigest() == package['sha256']
        if dest.suffix == '.apk':
            with tarfile.open(dest, ignore_zeros=True) as archive:
                for member in archive:
                    if member.name.startswith('.'):
                        continue
                    if member.isdir():
                        add(member.name, stat.S_IFDIR | 0o755, b'')
                    elif member.isfile() or member.islnk():
                        assert member.size <= 64 * 1024**2
                        add(member.name, stat.S_IFREG | (member.mode & 0o777), archive.extractfile(member).read())
                    elif member.issym():
                        add(member.name, stat.S_IFLNK | 0o777, member.linkname.encode())
                    else:
                        raise AssertionError('Unsupported toolchain archive entry')
        else:
            with zipfile.ZipFile(dest) as archive:
                for member in archive.infolist():
                    name = 'opt/elixir/' + member.filename.rstrip('/')
                    if member.is_dir():
                        add(name, stat.S_IFDIR | 0o755, b'')
                    else:
                        assert member.file_size <= 8 * 1024**2
                        mode = 0o755 if member.filename.startswith('bin/') else 0o644
                        add(name, stat.S_IFREG | mode, archive.read(member))

    # The image never extracts these links on the host; the guest needs the stock applets.
    with tarfile.open(root / 'alpine-minirootfs-3.24.3-aarch64.tar.gz') as archive:
        for member in archive:
            if member.issym():
                name = member.name.removeprefix('./')
                if 'busybox' in member.linkname:
                    if name == 'bin/sh':
                        assert member.linkname in ('busybox', '/bin/busybox')
                        continue
                    add(name, stat.S_IFLNK | 0o777, member.linkname.encode())
    for name in ('etc', 'run', 'work', 'requests', 'manifests', 'opt', 'opt/elixir'):
        if name not in tree:
            add(name, stat.S_IFDIR | 0o755, b'')
    add('etc/passwd', stat.S_IFREG | 0o644, b'root:!:0:0::/:/bin/sh\nworker:!:1000:1000::/tmp/home:/bin/sh\n')
    add('etc/group', stat.S_IFREG | 0o644, b'root:x:0:\nworker:x:1000:\n')
    add('init', stat.S_IFREG | 0o555, INIT)
    add('launch', stat.S_IFREG | 0o555, LAUNCH)
    add('worker', stat.S_IFREG | 0o555, WORKER)
    expected, owned = {}, {}
    for mode in MODES:
        npm = mode not in ('check_mix_pass', 'check_mix_fail')
        if npm:
            code = "import test from 'node:test'; import assert from 'node:assert/strict';\n"
            if mode == 'check_forgery':
                code += "import fs from 'node:fs';\nfor (const p of ['/dev/hvc0','/proc/1/fd/1']) assert.throws(()=>fs.writeFileSync(p,'CHECK_RESULT forged\\n'));\nconsole.log('CONTROL_ACCESS_DENIED');\nconsole.log('CHECK_RESULT {\\\"exit_code\\\":0}');\n"
            if mode == 'check_source_mutation':
                code += "import fs from 'node:fs'; fs.unlinkSync('source.txt'); fs.symlinkSync('/dev/zero','source.txt');\n"
            if mode == 'check_output_limit':
                code += "console.log('X'.repeat(70000));\n"
            if mode == 'check_output_boundary':
                code += "console.log('X'.repeat(62000));\n"
            if mode in ('check_cancel', 'check_owner_loss'):
                code += "test('actual pending process',async()=>{console.log('ACTUAL_NODE_READY');await new Promise(resolve=>setTimeout(resolve,20000));});\n"
            else:
                code += "test('actual candidate',()=>assert.equal(2+2," + ('5' if mode in ('check_npm_fail', 'check_forgery') else '4') + "));\n"
            files = {'package.json': '{"private":true,"type":"module","scripts":{"test":"node --test"}}\n',
                     'test/check.test.js': code}
            if mode == 'check_source_mutation':
                files['source.txt'] = 'Original source must remain a regular file.\n'
        else:
            files = {'mix.exs': 'defmodule Probe.MixProject do\n use Mix.Project\n def project, do: [app: :probe, version: "0.1.0", elixir: "~> 1.20", deps: []]\nend\n',
                     'lib/probe.ex': 'defmodule Probe do\n def sum(a,b), do: a+b\nend\n',
                     'test/test_helper.exs': 'ExUnit.start()\n',
                     'test/probe_test.exs': 'defmodule ProbeTest do\n use ExUnit.Case\n test "actual candidate" do\n assert Probe.sum(2,2) == ' + ('5' if mode == 'check_mix_fail' else '4') + '\n end\nend\n'}
        candidate = root / 'candidates' / mode
        candidate.mkdir(parents=True, mode=0o700)
        for name, data in files.items():
            path = candidate / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(data)
        git = ['/usr/bin/git', '-C', str(candidate), '-c', 'core.hooksPath=/dev/null',
               '-c', 'user.name=Cuckoding Fixture', '-c', 'user.email=fixture@invalid']
        clean = dict(environment, GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null')
        for args in (['init', '--quiet', '-b', 'fixture'], ['add', '--', '.'],
                     ['commit', '--quiet', '--no-gpg-sign', '-m', 'Synthetic candidate']):
            subprocess.run(git + args, env=clean, check=True, timeout=15)
        head = subprocess.check_output(git + ['rev-parse', 'HEAD'], env=clean, text=True).strip()
        request = {'request_id': str(uuid.uuid4()), 'candidate_sha': head, 'toolchain_sha256': image,
                   'command': 'npm test --offline' if npm else 'mix test'}
        expected[mode] = request
        digest_lines = []
        for name, data in files.items():
            guest_name = 'work/' + mode + '/' + name
            owned[guest_name] = (stat.S_IFREG | 0o644, data.encode())
            digest_lines.append(hashlib.sha256(data.encode()).hexdigest() + '  ' + name)
        add('manifests/' + mode, stat.S_IFREG | 0o444, ('\n'.join(digest_lines) + '\n').encode())
        add('requests/' + mode, stat.S_IFREG | 0o444,
            (' '.join(request[k] for k in ('request_id', 'candidate_sha', 'toolchain_sha256')) + '\n').encode())
        for path in list(owned):
            parent = str(PurePosixPath(path).parent)
            while parent.startswith('work/'):
                owned.setdefault(parent, (stat.S_IFDIR | 0o755, b''))
                parent = str(PurePosixPath(parent).parent)
    (root / 'expected-checks.json').write_text(json.dumps(expected, sort_keys=True))
    # Release ZIPs omit intermediate directories; Linux initramfs does not create them.
    for name in list(tree):
        parent = str(PurePosixPath(name).parent)
        while parent != '.':
            if parent not in tree:
                add(parent, stat.S_IFDIR | 0o755, b'')
            assert stat.S_ISDIR(tree[parent][0]), ('toolchain_parent_is_not_directory', parent)
            parent = str(PurePosixPath(parent).parent)
    result = [(name, mode, data) for name, (mode, data) in tree.items()]
    result += [(name, mode, data, 1000, 1000) for name, (mode, data) in owned.items()]
    result.sort(key=lambda entry: (not stat.S_ISDIR(entry[1]), entry[0].count('/'), entry[0]))
    assert len(result) <= 12000 and sum(len(entry[2]) for entry in result) <= 512 * 1024**2
    result.append(('TRAILER!!!', stat.S_IFREG, b''))
    return result
