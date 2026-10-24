"""Opt-in Darwin/arm64 VM prerequisite probe; never enables an application grant.

Downloads ~100 MB of pinned official Alpine inputs into a fresh private folder.
Requires Xcode's Swift compiler. No guest network, host share, project or provider.
Retains all artifacts; owner-loss observations never establish verified cleanup.
"""
from pathlib import Path
import gzip
import hashlib
import io
import json
import os
import selectors
import shutil
import stat
import struct
import subprocess
import tempfile
import time

project = Path(__file__).resolve().parent.parent
assert os.uname().sysname == 'Darwin' and os.uname().machine == 'arm64'
assert shutil.disk_usage('/private/tmp').free >= 2 * 1024**3
os.umask(0o077)
root = Path(tempfile.mkdtemp(prefix='cuckoding-r050j-', dir='/private/tmp'))
assert root.resolve() == root
root.chmod(0o700)
environment = {'HOME': str(root), 'TMPDIR': str(root), 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
               'LANG': 'en_US.UTF-8'}
print(json.dumps({'fixture_root': str(root)}), flush=True)
inputs = {
    'alpine-virt-3.24.3-aarch64.iso': 'e34603080e942e9ebc670689eee77dd7a6551c823a6ff5a299e308ded268098f',
    'alpine-minirootfs-3.24.3-aarch64.tar.gz': '4d3f80afaebd447c5591a63a73bde380a149fe8b2d85488cafabb2ff97551f50',
}


def run(args, **options):
    return subprocess.run(args, env=environment, cwd=root, check=True, **options)


for name, digest in inputs.items():
    url = 'https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/aarch64/' + name
    run(['/usr/bin/curl', '--disable', '--fail', '--location', '--proto', '=https',
         '--tlsv1.2', '--connect-timeout', '10', '--max-time', '120', '--max-filesize', '134217728',
         '--silent', '--show-error', '--output', str(root / name), url], timeout=125)
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest

raw = run(['/usr/bin/tar', '-xOf', str(root / 'alpine-virt-3.24.3-aarch64.iso'),
           'boot/vmlinuz-virt'], capture_output=True, timeout=15).stdout
# The pinned EFI zboot header locates its gzip payload; do not execute EFI code.
assert raw[4:8] == b'zimg' and raw[24:29] == b'gzip\0'
offset, size = struct.unpack_from('<II', raw, 8)
assert 0 < offset < len(raw) and 0 < size <= len(raw) - offset
with gzip.GzipFile(fileobj=io.BytesIO(raw[offset:offset + size])) as stream:
    kernel = stream.read(128 * 1024**2 + 1)
assert len(kernel) <= 128 * 1024**2 and kernel[56:60] == b'ARM\x64'
(root / 'kernel').write_bytes(kernel)

# Select only two regular package members into memory; never extract host links/devices.
import tarfile
with tarfile.open(root / 'alpine-minirootfs-3.24.3-aarch64.tar.gz') as archive:
    files = {}
    for name in ('./bin/busybox', './lib/ld-musl-aarch64.so.1'):
        member = archive.getmember(name)
        assert member.isfile() and member.size < 2 * 1024**2
        files[name[2:]] = archive.extractfile(member).read()

init = b'''#!/bin/sh
/bin/busybox mount -t devtmpfs devtmpfs /dev
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sysfs /sys
# Trusted probe only; this watchdog is not yet an untrusted-toolchain policy.
(/bin/busybox sleep 40; echo GUEST_WATCHDOG; /bin/busybox poweroff -f) &
echo GUEST_INIT
/bin/busybox setsid /bin/sh /child A &
/bin/busybox setsid /bin/sh -c '/bin/busybox setsid /bin/sh /child B </dev/null >/dev/hvc0 2>&1 &' &
echo GUEST_READY
while :; do /bin/busybox sleep 1; done
'''
child_script = b'''#!/bin/sh
read pid comm state ppid pgrp session rest < /proc/self/stat
echo "GUEST_CHILD $1 pid=$pid ppid=$ppid pgrp=$pgrp session=$session"
i=0
while [ "$i" -lt 30 ]; do echo "GUEST_TICK $1 $i"; i=$((i+1)); /bin/busybox sleep 1; done
'''
entries = [(name, stat.S_IFDIR | 0o755, b'') for name in ('bin', 'lib', 'dev', 'proc', 'sys', 'tmp')]
entries += [(name, stat.S_IFREG | 0o755, data) for name, data in files.items()]
entries += [('bin/sh', stat.S_IFLNK | 0o777, b'busybox'), ('init', stat.S_IFREG | 0o755, init),
            ('child', stat.S_IFREG | 0o755, child_script), ('TRAILER!!!', stat.S_IFREG, b'')]
cpio = bytearray()
for inode, (name, mode, data) in enumerate(entries, 1):
    encoded = name.encode() + b'\0'
    fields = [inode, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(encoded), 0]
    cpio.extend(b'070701' + b''.join(f'{field:08x}'.encode() for field in fields) + encoded)
    cpio.extend(b'\0' * (-len(cpio) % 4))
    cpio.extend(data)
    cpio.extend(b'\0' * (-len(cpio) % 4))
(root / 'probe.cpio.gz').write_bytes(gzip.compress(bytes(cpio), mtime=0))
(root / 'entitlements.plist').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>com.apple.security.virtualization</key><true/></dict></plist>''')
source = root / 'Probe.swift'
source.write_bytes((project / 'test/support/guest_lifetime_probe.swift').read_bytes())
run(['/usr/bin/xcrun', 'swiftc', '-swift-version', '6', '-default-isolation', 'MainActor',
     '-warnings-as-errors', '-module-cache-path', str(root / 'module-cache'), str(source),
     '-framework', 'Virtualization', '-o', str(root / 'probe')], timeout=120)
run(['/usr/bin/codesign', '--force', '--sign', '-', '--entitlements',
     str(root / 'entitlements.plist'), str(root / 'probe')], timeout=10)
run(['/usr/bin/codesign', '--verify', '--strict', str(root / 'probe')], timeout=10)

# Path/mode refusals occur before the VM is created.
for args, status in [([], 64), ([str(root), 'unknown'], 64), (['/tmp/' + root.name, 'input'], 65)]:
    result = subprocess.run([str(root / 'probe'), *args], env=environment, cwd=root, timeout=10)
    assert result.returncode == status


def observe(mode):
    child = subprocess.Popen([str(root / 'probe'), str(root), mode], cwd=root, env=environment,
                             start_new_session=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, bufsize=0)
    selector = selectors.DefaultSelector()
    selector.register(child.stdout, selectors.EVENT_READ)
    began = time.monotonic()
    records, groups, ticks = [], {}, set()
    total, released, eof = 0, False, False
    try:
        with (root / ('mode-' + mode + '.log')).open('xb') as output:
            while time.monotonic() - began < 45:
                if not selector.select(timeout=0.25):
                    continue
                line = child.stdout.readline(4097)
                if not line:
                    eof = True
                    break
                total += len(line)
                assert len(line) <= 4096 and total <= 131072
                output.write(line)
                output.flush()
                if line.startswith(b'HOST '):
                    records.append(json.loads(line[5:]))
                if line.startswith(b'GUEST_CHILD '):
                    parts = line.decode().split()
                    groups[parts[1]] = {k: int(v) for k, v in (field.split('=') for field in parts[2:])}
                if line.rstrip(b'\r\n') in (b'GUEST_TICK A 1', b'GUEST_TICK B 1'):
                    ticks.add(line.split()[1].decode())
                if ticks == {'A', 'B'} and mode != 'deadline' and not released:
                    if mode == 'owner_loss':
                        # The owned leader is still unreaped; this cannot target a reused PID.
                        assert child.poll() is None
                        child.terminate()
                    elif mode == 'eof':
                        child.stdin.close()
                    else:
                        child.stdin.write(b'x')
                        child.stdin.flush()
                    released = True
        assert eof, 'Output did not close inside the trusted guest lifetime bound'
        child.wait(timeout=10)
    finally:
        if not child.stdin.closed:
            child.stdin.close()
        if child.poll() is None:
            child.wait(timeout=45)
        selector.close()
        child.stdout.close()
    assert ticks == {'A', 'B'} and set(groups) == {'A', 'B'}
    assert all(value['pid'] == value['pgrp'] == value['session'] and value['ppid'] == 1
               for value in groups.values())
    assert groups['A']['session'] != groups['B']['session']
    receipt_path = root / ('stop-' + mode + '.json')
    if mode == 'owner_loss':
        assert child.returncode == -15 and not receipt_path.exists()
        verified = False  # EOF/owner absence is not VM cleanup proof.
    else:
        assert child.returncode == 0
        receipt = json.loads(receipt_path.read_bytes())
        reason = {'input': 'controller_input', 'eof': 'controller_eof', 'deadline': 'deadline',
                  'paused': 'paused_controller'}[mode]
        assert receipt['state'] == 0 and receipt['reason'] == reason
        assert any(row.get('event') == 'stopped' and row.get('state') == 0 for row in records)
        if mode == 'paused':
            assert any(row.get('event') == 'paused' and row.get('state') == 2 for row in records)
        if mode == 'deadline':
            assert time.monotonic() - began >= 9
        verified = True
    result = {'mode': mode, 'seconds': round(time.monotonic() - began, 3),
              'isolated_guest_sessions': True, 'native_stopped_observed': verified,
              'missing_receipt_is_unverified': mode == 'owner_loss'}
    print(json.dumps(result), flush=True)
    return result


outcomes = [observe(mode) for mode in ('input', 'eof', 'deadline', 'paused', 'owner_loss')]
result = {'fixture_root': str(root), 'inputs': inputs, 'cpus': 2, 'memory_mib': 512,
          'network': False, 'host_shares': False, 'shipping_grant_changed': False,
          'outcomes': outcomes, 'owner_loss_cleanup_authority': False,
          'hashes': {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
                     for name in ('kernel', 'probe.cpio.gz', 'Probe.swift', 'probe')}}
(root / 'evidence.json').write_text(json.dumps(result, indent=2) + '\n')
print('PASS: native guest stop observations; owner loss remains unverified, toolchain grants unchanged.', flush=True)
