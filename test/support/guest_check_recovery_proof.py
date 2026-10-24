"""Source-only exact native inspection proof; caller owns a fresh synthetic fixture."""
import copy
import hashlib
import json
from pathlib import Path
import sqlite3
import stat
import subprocess


def verify(root, helper, checks):
    assert root.parent == Path('/private/tmp') and root.name.startswith('cuckoding-r060t-')
    assert root.resolve() == root and not root.is_symlink()
    assert (root / '.fixture-v1').read_bytes() == b'guest-battle-fixture-v1\n'
    assert root.stat().st_mode & 0o777 == 0o700
    data = root / 'data'
    runs = data / 'runtime-home/check-runs'
    probes = root / 'inspection-probes'
    probes.mkdir(mode=0o700)
    counter = 0

    def fingerprint():
        return {str(p.relative_to(runs)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in runs.glob('*/*') if p.is_file()}

    def source_fingerprint():
        source = root / 'source'
        return {str(p.relative_to(source)): (p.stat().st_ino, p.stat().st_mode,
                                            hashlib.sha256(p.read_bytes()).hexdigest())
                for p in source.rglob('*') if p.is_file()}

    def inspect(query, source):
        nonlocal counter
        counter += 1
        output = probes / f'{counter}.json'
        args = [str(helper), '--arena-git', 'recover_guest_check', source['path'],
                str(source['device']), str(source['inode']), str(data / 'runtime-home'),
                json.dumps(query, separators=(',', ':'))]
        with output.open('xb') as stream:
            output.chmod(0o600)
            child = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=stream,
                                     stderr=subprocess.DEVNULL, cwd=root,
                                     env={'HOME': str(root / 'discovery-home'),
                                          'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LANG': 'C'})
            try:
                assert child.wait(timeout=65) == 0
            except subprocess.TimeoutExpired:
                child.stdin.close()
                child.wait(timeout=5)
                raise
            finally:
                child.stdin.close()
        metadata = output.lstat()
        assert stat.S_ISREG(metadata.st_mode) and metadata.st_nlink == 1 and metadata.st_size <= 16384
        row = json.loads(output.read_bytes())
        row.pop('elapsed_ms', None)
        return row

    original = fingerprint()
    original_source = source_fingerprint()
    before_runs = sorted(p.name for p in runs.iterdir())
    positive = []
    with sqlite3.connect((data / 'foundation.db').as_uri() + '?mode=ro', uri=True) as db:
        for row in checks:
            request = json.loads(db.execute('SELECT request FROM battle_attempts WHERE id=?',
                                           (row['request_id'],)).fetchone()[0])
            declaration = next(c for c in request['snapshot']['checks'] if c['id'] == row['id'])
            candidate = (request['task_context']['candidate_sha'] if request['task_id']
                         else request['context']['head'])
            query = {'contract': 'retained-guest-check-v1',
                     'key': request['guest_check_runs'][row['id']],
                     'check': {'request_id': request['request_id'], 'check_id': declaration['id'],
                               'input_key': request['request_id'], 'candidate_sha': candidate,
                               'toolchain': declaration['executable'],
                               **{k: declaration[k] for k in ('directory', 'arguments', 'timeout_seconds')}},
                     'image': request['context']['check_image'],
                     'feedback': request['snapshot']['check_feedback']}
            source = request['snapshot']['source']
            expected = json.loads((runs / row['key'] / 'receipt.json').read_bytes())
            assert inspect(query, source) == expected
            assert inspect(query, source) == expected
            positive.append((query, source))

    query, source = positive[0]
    rejected = 0
    for field, value in [('key', '00000000-0000-4000-8000-000000000099'),
                         ('feedback', 'unknown'), ('path', '/private/tmp/arbitrary-log')]:
        altered = copy.deepcopy(query)
        altered[field] = value
        assert inspect(altered, source).get('cleanup_verified') is not True
        rejected += 1
    for field, value in [('candidate_sha', 'f' * 40), ('arguments', ['test', '--unsafe'])]:
        altered = copy.deepcopy(query)
        altered['check'][field] = value
        assert inspect(altered, source).get('cleanup_verified') is not True
        rejected += 1
    assert inspect(query, {**source, 'inode': source['inode'] + 1}).get('cleanup_verified') is not True
    rejected += 1

    receipt = runs / query['key'] / 'receipt.json'
    saved = receipt.with_name('receipt.saved')
    receipt.rename(saved)
    try:
        assert inspect(query, source).get('cleanup_verified') is not True
        rejected += 1
    finally:
        saved.rename(receipt)
    assert inspect(query, source) == json.loads(receipt.read_bytes())
    assert before_runs == sorted(p.name for p in runs.iterdir())
    assert original == fingerprint()
    assert original_source == source_fingerprint()
    return {'verified_original_checks': len(positive), 'repeatable': True,
            'rejected_foreign_or_partial': rejected, 'no_vm_or_artifact_replay': True,
            'original_artifacts_unchanged': True, 'source_and_index_preserved': True,
            'workflow_recovery_enabled': False}
