"""Sealed native candidate-input protocol, fresh synthetic folders only; no providers."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import tempfile
import uuid

os.umask(0o077)
project = Path(__file__).resolve().parent.parent
app = project / 'desktop/src-tauri/target/release/bundle/macos/Cuckoding.app'
subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True, timeout=60)
binary = app / 'Contents/MacOS/ccoding'
root = Path(tempfile.mkdtemp(prefix='cuckoding-r050m-cli-', dir='/private/tmp'))
assert root.resolve() == root
source, home, replies = (root / name for name in ('source', 'home', 'replies'))
for directory in (source, home, replies):
    directory.mkdir(mode=0o700)
identity = source.stat()
environment = {'HOME': str(home), 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LANG': 'en_US.UTF-8',
               'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_SYSTEM': '/dev/null', 'GIT_CONFIG_GLOBAL': '/dev/null'}
observations = []
print(json.dumps({'fixture_root': str(root)}), flush=True)


def native(operation, request=None):
    args = [str(binary), '--arena-git', operation, str(source), str(identity.st_dev),
            str(identity.st_ino), str(home)]
    if request is not None:
        args.append(json.dumps(request, separators=(',', ':')))
    output = replies / (str(uuid.uuid4()) + '.json')
    with output.open('xb') as stream:
        child = subprocess.Popen(args, cwd=root, env=environment, stdin=subprocess.PIPE,
                                 stdout=stream, stderr=subprocess.DEVNULL)
        try:
            child.wait(timeout=65)
        except subprocess.TimeoutExpired:
            child.stdin.close()
            child.wait(timeout=5)
            raise AssertionError('Native operation exceeded its bound')
        finally:
            if not child.stdin.closed:
                child.stdin.close()
    assert child.returncode == 0 and output.stat().st_size <= 8192
    value = json.loads(output.read_bytes())
    observations.append({'operation': operation, 'status': value.get('status')})
    return {key: value for key, value in value.items() if key not in ('elapsed_ms', 'cleanup_verified')}


assert native('init')['status'] == 'initialized'
(source / 'package.json').write_text('{"private":true,"scripts":{"test":"node --test"}}\n')
(source / 'result.txt').write_bytes(b'committed input\x00\xff\n')
for args in (['add', '--', 'package.json', 'result.txt'],
             ['commit', '--quiet', '--no-gpg-sign', '-m', 'Synthetic candidate']):
    subprocess.run(['/usr/bin/git', '-C', str(source), '-c', 'core.hooksPath=/dev/null',
                    '-c', 'user.name=Cuckoding Fixture', '-c', 'user.email=fixture@invalid', *args],
                   cwd=root, env=environment, check=True, timeout=10, stdout=subprocess.DEVNULL)
head = native('inspect')['head']
preparation = native('worktree', {'key': str(uuid.uuid4()), 'head': head})
assert preparation['status'] == 'prepared'
index = (source / '.git/index').read_bytes()
(source / 'result.txt').write_text('UNCOMMITTED_USER_CANARY')
key = str(uuid.uuid4())
request = {'key': key, 'preparation': preparation}
receipt = native('prepare_check_input', request)
assert receipt['status'] == 'check_input_prepared' and receipt['candidate_sha'] == head
owned = home / 'check-inputs' / key
archive = (owned / 'candidate.cpio').read_bytes()
assert len(archive) == receipt['archive_bytes']
assert hashlib.sha256(archive).hexdigest() == receipt['archive_sha256']
assert b'committed input\x00\xff\n' in archive and b'UNCOMMITTED_USER_CANARY' not in archive
proof = {name: (owned / name).read_bytes() for name in ('intent.json', 'receipt.json', 'manifest.json', 'candidate.cpio')}
for _ in range(2):
    verified = native('verify_check_input', dict(request, input=receipt))
    assert verified == dict(receipt, status='check_input_verified')
    assert {name: (owned / name).read_bytes() for name in proof} == proof
assert native('prepare_check_input', request)['status'] == 'check_input_exists'
(owned / 'candidate.cpio').write_bytes(b'tampered')
assert native('verify_check_input', dict(request, input=receipt))['status'] == 'check_input_mismatch'
assert (owned / 'candidate.cpio').read_bytes() == b'tampered'
(owned / 'receipt.json').unlink()
assert native('verify_check_input', dict(request, input=receipt))['status'] == 'check_input_mismatch'
assert not (owned / 'receipt.json').exists()
assert (source / 'result.txt').read_text() == 'UNCOMMITTED_USER_CANARY'
assert (source / '.git/index').read_bytes() == index
result = {'fixture_root': str(root), 'helper_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
          'operations': observations, 'repeat_read_preserved_artifacts': True, 'inference': False,
          'tamper_and_missing_receipt_refused': True, 'source_preserved': True}
(root / 'evidence.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result), flush=True)
