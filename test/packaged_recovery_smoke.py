"""Darwin sealed-app recovery regression; fresh synthetic workspaces, no inference.

Run with the pinned Elixir/OTP toolchain on PATH after bin/dev.build. Failed
fixtures and private logs are retained; this script never accepts a data root.
"""
from pathlib import Path
import contextlib
import fcntl
import hashlib
import json
import os
import queue
import sqlite3
import subprocess
import tempfile
import threading
import time
import uuid

project = Path(__file__).resolve().parent.parent
app = project / 'desktop/src-tauri/target/release/bundle/macos/Cuckoding.app'
binary = app / 'Contents/MacOS/ccoding'
release = app / 'Contents/Resources/release'
artifact = project / '.ccoding/packaged-recovery-smoke.json'
subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
assert binary.is_file() and release.is_dir()
build = json.loads((release / 'lib/cuckoding-0.1.0/priv/build-info.json').read_bytes())


def private_write(path, value):
    with path.open('x') as stream:
        path.chmod(0o600)
        stream.write(value)


def fresh_root():
    root = Path(tempfile.mkdtemp(prefix='cuckoding-packaged-recovery-', dir='/private/tmp'))
    root.chmod(0o700)
    return root


def refuse_unsafe_fixtures():
    root = fresh_root()
    sentinel = root / 'preserve.txt'
    private_write(sentinel, 'Do not modify this fixture.\n')
    linked = fresh_root()
    linked.rmdir()
    linked.symlink_to(root, target_is_directory=True)
    for target in (root, linked):
        log = project / '.ccoding' / (target.name + '-refused.log')
        with log.open('xb') as output:
            log.chmod(0o600)
            environment = dict(os.environ, MIX_ENV='test', CUCKODING_PACKAGED_FIXTURE_ROOT=str(target))
            result = subprocess.run(['rtk', 'proxy', 'mix', 'run', '--no-start',
                                     'test/support/packaged_recovery_fixture.exs'], cwd=project,
                                    env=environment, stdout=output, stderr=subprocess.STDOUT,
                                    timeout=30)
        assert result.returncode != 0
        assert list(root.iterdir()) == [sentinel]
        assert sentinel.read_bytes() == b'Do not modify this fixture.\n'
        assert sentinel.stat().st_mode & 0o777 == 0o600
        assert linked.is_symlink() and linked.resolve() == root


def fixture():
    root = fresh_root()
    private_write(root / '.fixture-v1', 'packaged-recovery-fixture-v1\n')
    data = root / 'data'
    data.mkdir(mode=0o700)
    log = project / '.ccoding' / (root.name + '-generator.log')
    # The source builder has no release CLI/API hook and refuses nonempty roots.
    with (data / 'shell.lock').open('x+b') as lock, log.open('xb') as output:
        (data / 'shell.lock').chmod(0o600)
        log.chmod(0o600)
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        environment = dict(os.environ, MIX_ENV='test', CUCKODING_PACKAGED_FIXTURE_ROOT=str(root))
        subprocess.run(['rtk', 'proxy', 'mix', 'run', '--no-start',
                        'test/support/packaged_recovery_fixture.exs'], cwd=project,
                       env=environment, stdout=output, stderr=subprocess.STDOUT,
                       check=True, timeout=600)
    expected = json.loads((root / 'expected.json').read_bytes())
    assert expected['format'] == 1 and expected['synthetic_provider'] is True
    for key in ('battle_id', 'attempt_id', 'arena_id', 'tabula_id'):
        assert str(uuid.UUID(expected[key])) == expected[key]
    return root, expected


def rows(root):
    # Keep all requests/claim tokens in memory; only public assertions are exported.
    with contextlib.closing(sqlite3.connect((root / 'data/foundation.db').as_uri() + '?mode=ro',
                                          uri=True, timeout=2)) as db:
        db.row_factory = sqlite3.Row
        assert db.execute('PRAGMA integrity_check').fetchall()[0][0] == 'ok'
        assert not db.execute('PRAGMA foreign_key_check').fetchall()
        return {table: [dict(row) for row in db.execute('SELECT * FROM ' + table + ' ORDER BY id')]
                for table in ('battles', 'battle_attempts', 'battle_tasks', 'draft_tasks',
                              'commands', 'events')}


def identity(pid):
    return subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'lstart=,comm='],
                          capture_output=True, text=True, timeout=3).stdout.strip()


@contextlib.contextmanager
def held(root, timeout_case=False):
    log = project / '.ccoding' / (root.name + '-shell-' + str(uuid.uuid4()) + '.log')
    messages = queue.Queue()
    environment = {'HOME': str(root / 'discovery-home'), 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
                   'LANG': 'en_US.UTF-8', 'TZ': 'UTC', 'CCODING_DATA_DIR': str(root / 'data'),
                   'CCODING_RELEASE_DIR': str(release)}
    child = subprocess.Popen([str(binary), '--smoke-test', '--wait-for-input'], cwd=root,
                             env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT)

    def collect():
        with log.open('xb') as stream:
            log.chmod(0o600)
            for line in child.stdout:
                assert len(line) <= 2048
                stream.write(line)
                stream.flush()
                messages.put(line)
        messages.put(None)

    reader = threading.Thread(target=collect, daemon=True)
    reader.start()
    started = time.monotonic()
    backend = None
    try:
        while time.monotonic() - started < 40:
            line = messages.get(timeout=40 - (time.monotonic() - started))
            assert line is not None, 'Shell exited before held readiness; inspect private shell log'
            if line == b'CCODING_SMOKE_HELD\n':
                break
        else:
            raise AssertionError('Shell held readiness timed out')
        processes = subprocess.check_output(['/bin/ps', '-axo', 'pid=,ppid=,comm='], text=True)
        owned = [int(parts[0]) for row in processes.splitlines()
                 if len(parts := row.split(None, 2)) == 3 and parts[1] == str(child.pid)
                 and parts[2].endswith('/beam.smp')]
        assert len(owned) == 1
        backend = owned[0], identity(owned[0])
        assert backend[1]
        held_at = time.monotonic()
        yield child
        if timeout_case:
            assert child.wait(timeout=100) == 1
            assert time.monotonic() - held_at >= 89
        else:
            # EOF models controller loss; callers may also send a release byte.
            child.stdin.close()
            assert child.wait(timeout=15) == 0
        reader.join(timeout=3)
        assert not reader.is_alive()
        text = log.read_text()
        assert ('PASS: bundled launch' in text) is not timeout_case
        assert identity(backend[0]) != backend[1], 'Owned backend survived shutdown'
        with (root / 'data/shell.lock').open('r+b') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    finally:
        if not child.stdin.closed:
            child.stdin.close()
        if child.poll() is None:
            child.wait(timeout=15)
        child.stdout.close()


def by_id(records, identifier):
    matches = [row for row in records if row['id'] == identifier]
    assert len(matches) == 1
    return matches[0]


def unchanged(before, after, excluded=()):
    assert {k: v for k, v in before.items() if k not in excluded} == {
        k: v for k, v in after.items() if k not in excluded}


def recovery(missing=False):
    root, expected = fixture()
    before = rows(root)
    battle = by_id(before['battles'], expected['battle_id'])
    attempt = by_id(before['battle_attempts'], expected['attempt_id'])
    assert battle['state'] == 'running' and attempt['state'] == 'running'
    assert attempt['stage'] == 'combine' and not attempt['role']
    assert len(before['battle_attempts']) == expected['attempts']
    proof = root / 'data/runtime-home/battles' / expected['battle_id'] / (
        'combination-' + expected['attempt_id'])
    assert proof.resolve() == proof and proof.is_dir()
    if missing:
        receipt = proof / 'receipt.json'
        assert receipt.is_file() and receipt.stat().st_nlink == 1
        receipt.unlink()
    retained = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in proof.iterdir()
                if p.is_file()}
    assert retained and ('receipt.json' in retained) is not missing
    with held(root) as child:
        deadline = time.monotonic() + 65
        while time.monotonic() < deadline:
            assert child.poll() is None
            after = rows(root)
            current = by_id(after['battles'], expected['battle_id'])
            context = json.loads(current['context'])
            observation = context.get('candidate_reconciliations', {}).get(expected['attempt_id'])
            if observation and not context.get('candidate_recovery_pending'):
                break
            time.sleep(0.2)
        else:
            raise AssertionError('Packaged recovery did not settle its read observation')
        assert current['state'] == ('needs_attention' if missing else 'paused')
        assert current['stage'] == ('combine' if missing else 'secutor')
        assert observation['receipt']['cleanup_verified'] is not missing
        assert observation['receipt']['status'] == ('failed' if missing else 'combined')
        assert observation['observed_at']
        unchanged(battle, current, ('state', 'stage', 'current_task_id', 'context', 'reason',
                                    'control_revision', 'updated_at'))
        assert context['head'] == expected['head']
        assert current['turns_used'] == expected['turns_used']
        interrupted = by_id(after['battle_attempts'], expected['attempt_id'])
        assert interrupted['state'] == 'interrupted'
        unchanged(attempt, interrupted, ('state', 'result', 'updated_at'))
        assert json.loads(interrupted['result'])['status'] == 'interrupted'
        assert len(after['battle_attempts']) == len(before['battle_attempts'])
        for old, new in zip(before['battle_attempts'], after['battle_attempts']):
            if old['id'] != attempt['id']:
                unchanged(old, new)
        assert before['draft_tasks'] == after['draft_tasks']
        assert before['commands'] == after['commands']
        for old, new in zip(before['battle_tasks'], after['battle_tasks']):
            if old['task_id'] == attempt['task_id']:
                unchanged(old, new, ('state', 'context', 'updated_at'))
                task_context = json.loads(new['context'])
                assert new['state'] == ('needs_attention' if missing else 'review')
                assert task_context['lane_stage'] == ('combine' if missing else 'secutor')
                if missing:
                    assert task_context == dict(json.loads(old['context']), column='review')
                else:
                    assert task_context['candidate_sha'] == expected['candidate_sha']
            else:
                unchanged(old, new)
        assert {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in proof.iterdir()
                if p.is_file()} == retained
        assert hashlib.sha256((root / 'source/.git/index').read_bytes()).hexdigest() == expected['source_index_sha256']
        assert (root / 'source/a.txt').read_bytes() == b'a base\n'
        assert (root / 'source/b.txt').read_bytes() == b'b base\n'
        if not missing:
            child.stdin.write(b'\n')
            child.stdin.flush()
    durable = rows(root)
    assert durable['battles'] == after['battles']
    assert durable['battle_attempts'] == after['battle_attempts']
    assert any(row['kind'] == 'shell.quit_requested' for row in durable['events'])
    with held(root):
        time.sleep(1.2)
        restarted = rows(root)
        assert restarted['battles'] == durable['battles']
        assert restarted['battle_attempts'] == durable['battle_attempts']
        assert restarted['battle_tasks'] == durable['battle_tasks']
    assert {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in proof.iterdir()
            if p.is_file()} == retained
    result = {'fixture_root': str(root), 'missing_proof': missing,
              'state': current['state'], 'stage': current['stage'],
              'history_and_budgets_preserved': True, 'no_provider_or_native_replay': True,
              'source_and_proof_preserved': True, 'second_restart_does_not_resume': True,
              'graceful_shutdown': True}
    print(json.dumps(result), flush=True)
    return result


refuse_unsafe_fixtures()
complete = recovery()
missing = recovery(missing=True)
timeout_root = fresh_root()
(timeout_root / 'data').mkdir(mode=0o700)
with held(timeout_root, timeout_case=True):
    pass
timeout_rows = rows(timeout_root)
assert not timeout_rows['battles'] and not timeout_rows['battle_attempts']
assert any(row['kind'] == 'shell.quit_requested' for row in timeout_rows['events'])
result = {'format': 1, 'build': build, 'helper_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
          'inference': False, 'provider': 'synthetic test-only adapter',
          'populated_and_linked_fixture_roots_refused': True,
          'scenarios': [complete, missing], 'timeout_shutdown': True,
          'timeout_fixture_root': str(timeout_root)}
artifact.write_text(json.dumps(result, indent=2) + '\n')
artifact.chmod(0o600)
print('PASS: packaged combined checkpoint, missing-proof refusal, input/EOF/timeout shutdown', flush=True)
