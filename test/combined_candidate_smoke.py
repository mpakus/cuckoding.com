"""Darwin packaged Git protocol regression; fresh fixtures only, no providers/inference."""
from pathlib import Path
import hashlib
import json
import subprocess
import tempfile
import uuid

project = Path(__file__).resolve().parent.parent
app = project / 'desktop/src-tauri/target/release/bundle/macos/Cuckoding.app'
subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
binary = app / 'Contents/MacOS/ccoding'
root = Path(tempfile.mkdtemp(prefix='cuckoding-r060s-cli-', dir='/private/tmp'))
root.chmod(0o700)
(project / '.ccoding/combined-candidate-smoke-root').write_text(str(root))
source, home, replies = (root / name for name in ('source', 'home', 'replies'))
for p in (source, home, replies):
    p.mkdir(mode=0o700)
identity = source.stat()
environment = {'HOME': str(home), 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
               'LANG': 'en_US.UTF-8', 'TZ': 'UTC', 'GIT_CONFIG_NOSYSTEM': '1',
               'GIT_CONFIG_SYSTEM': '/dev/null', 'GIT_CONFIG_GLOBAL': '/dev/null'}
operations = []


def native(operation, request=None):
    args = [str(binary), '--arena-git', operation, str(source),
            str(identity.st_dev), str(identity.st_ino), str(home)]
    if request is not None:
        args.append(json.dumps(request, separators=(',', ':')))
    output = replies / (str(uuid.uuid4()) + '.json')
    with output.open('xb') as stream:
        output.chmod(0o600)
        child = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=stream,
                                 stderr=subprocess.DEVNULL, env=environment, cwd=root)
        try:
            child.wait(timeout=65)
        except subprocess.TimeoutExpired:
            child.stdin.close()
            child.wait(timeout=5)
            raise AssertionError('Native operation exceeded its fixed budget')
        finally:
            if not child.stdin.closed:
                child.stdin.close()
    assert child.returncode == 0
    assert output.stat().st_size <= 8192
    value = json.loads(output.read_bytes())
    operations.append({'operation': operation, 'status': value.get('status')})
    return {k: v for k, v in value.items() if k not in ('elapsed_ms', 'cleanup_verified')}


def git(*args):
    return subprocess.run(['/usr/bin/git', '-C', str(source), '-c', 'core.hooksPath=/dev/null',
                           '-c', 'user.name=Cuckoding Fixture', '-c', 'user.email=fixture@invalid',
                           *args], env=environment, cwd=root, check=True,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)


assert native('init')['status'] == 'initialized'
for name in ('a.txt', 'b.txt'):
    (source / name).write_text(name + ' base\n')
git('add', '--', 'a.txt', 'b.txt')
git('commit', '--quiet', '--no-gpg-sign', '-m', 'Synthetic baseline')
head = native('inspect')['head']
battle = native('create_battle', {'key': str(uuid.uuid4()), 'head': head})
assert battle['status'] == 'battle_created'
writers = []
for name in ('a.txt', 'b.txt'):
    prepared = native('battle_worktree', {'key': str(uuid.uuid4()), 'battle': battle})
    assert prepared.get('status', 'prepared') == 'prepared'
    preparation = {k: prepared[k] for k in ('key', 'head', 'path', 'device', 'inode')}
    assert Path(preparation['path']).resolve() == home / 'worktrees' / preparation['key'] / 'checkout'
    content = (name + ' result\n').encode()
    (Path(preparation['path']) / name).write_bytes(content)
    candidate = native('capture_candidate', {'key': str(uuid.uuid4()), 'preparation': preparation,
                                          'files': [{'path': name, 'sha256': hashlib.sha256(content).hexdigest()}]})
    assert candidate['status'] == 'candidate_captured'
    writers.append((preparation, candidate))
first, first_candidate = writers[0]
second, second_candidate = writers[1]
battle = native('integrate_candidate', {'key': str(uuid.uuid4()), 'battle': battle,
                                     'preparation': first, 'candidate': first_candidate})
assert battle['status'] == 'battle_integrated'
request = {'key': str(uuid.uuid4()), 'battle': battle, 'preparation': second, 'candidate': second_candidate}
combined = native('combine_candidate', request)
assert combined['status'] == 'candidate_combined'
(source / 'a.txt').write_text('USER_WORKING_FIXTURE\n')
index = (source / '.git/index').read_bytes()
directory = home / 'battles' / battle['battle_key'] / ('combination-' + request['key'])
proof = {name: (directory / name).read_bytes() for name in ('intent.json', 'publication.json', 'receipt.json', 'index')}
for _ in range(2):
    assert native('recover_combined_candidate', request) == combined
    assert (source / '.git/index').read_bytes() == index
    assert (source / 'a.txt').read_text() == 'USER_WORKING_FIXTURE\n'
    assert {name: (directory / name).read_bytes() for name in proof} == proof
assert native('verify_battle', {'battle': battle})['head'] == battle['head']
(directory / 'receipt.json').unlink()
assert native('recover_combined_candidate', request)['status'] == 'candidate_mismatch'
assert not (directory / 'receipt.json').exists()
assert native('combine_candidate', request)['status'] == 'candidate_exists'
result = {'fixture_root': str(root), 'operations': operations, 'inference': False,
          'repeated_read_preserves_proof': True, 'missing_receipt_not_recreated': True,
          'source_index_and_working_edits_preserved': True}
(project / '.ccoding/combined-candidate-smoke.json').write_text(json.dumps(result, indent=2))
print(json.dumps(result))
