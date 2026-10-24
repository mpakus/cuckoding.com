"""Test only the isolated-check decoder with synthetic frames, without booting a VM."""
from pathlib import Path
import json
import os
import subprocess
import tempfile

assert os.uname().sysname == 'Darwin'
os.umask(0o077)
project = Path(__file__).resolve().parent.parent
root = Path(tempfile.mkdtemp(prefix='cuckoding-check-decoder-', dir='/private/tmp'))
environment = {'HOME': str(root), 'TMPDIR': str(root), 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin'}
(root / 'Control.swift').write_bytes((project / 'test/support/guest_check_control.swift').read_bytes())
(root / 'main.swift').write_text(r'''
import Foundation
import CryptoKit

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let mode = CommandLine.arguments[2]
let expected = ["request_id": "00000000-0000-4000-8000-000000000001",
                "candidate_sha": String(repeating: "a", count: 40),
                "toolchain_sha256": String(repeating: "b", count: 64), "command": "mix test"]
try JSONSerialization.data(withJSONObject: [mode: expected]).write(to: root.appendingPathComponent("expected-checks.json"))
let control = try GuestCheckControl(root: root, mode: mode)
let output = Data("synthetic output\n".utf8)
var row: [String: Any] = expected
row["stdout_bytes"] = output.count
row["stdout_base64"] = output.base64EncodedString()
row["stdout_sha256"] = SHA256.hash(data: output).map({ String(format: "%02x", $0) }).joined()
row["source_unchanged"] = true
row["exit_code"] = 0
func bytes(_ value: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
precondition(control.valid(row, bytes(row)))
let mutations: [(String, Any?)] = [
    ("request_id", "00000000-0000-4000-8000-000000000002"),
    ("candidate_sha", String(repeating: "c", count: 40)),
    ("toolchain_sha256", String(repeating: "d", count: 64)),
    ("command", "npm test --offline"), ("extra", "untrusted"), ("exit_code", nil),
    ("exit_code", true), ("exit_code", "0"), ("exit_code", 0.5), ("exit_code", -1), ("exit_code", 256),
    ("stdout_bytes", true), ("stdout_bytes", -1), ("stdout_bytes", 65537),
    ("stdout_bytes", output.count + 1), ("stdout_base64", "invalid"),
    ("stdout_base64", Data("changed\n".utf8).base64EncodedString()),
    ("stdout_sha256", String(repeating: "0", count: 64)), ("stdout_sha256", String(repeating: "A", count: 64)),
    ("source_unchanged", 1), ("source_unchanged", "true")]
for (key, value) in mutations {
    var changed = row
    changed[key] = value
    precondition(!control.valid(changed, bytes(changed)), "Accepted invalid field: \(key)")
}
if mode == "failed" { row["exit_code"] = 1 }
if mode == "changed" { row["source_unchanged"] = false }
let frame = Data("CHECK_RESULT ".utf8) + bytes(row) + Data("\r\n".utf8)
if mode == "native_first" {
    control.stopped()
    control.receive(frame)
} else {
    let split = frame.count / 2
    control.receive(frame.prefix(split))
    precondition(control.result == nil)
    control.receive(frame.suffix(frame.count - split))
    precondition(control.result != nil)
    control.finishIfReady()
    precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent("stop-\(mode).json").path))
    if mode == "missing_native" { exit(0) }
    if mode == "duplicate" { control.receive(frame) }
    if mode == "invalid_utf8" { control.receive(Data([255, 10])) }
    if mode == "overflow" { control.receive(Data(repeating: 65, count: 131073)) }
    if mode == "cancelled" { control.cancellation = "cancelled" }
    control.stopped()
}
RunLoop.main.run()
''')
subprocess.run(['/usr/bin/xcrun', 'swiftc', '-swift-version', '6', '-default-isolation', 'MainActor',
                '-warnings-as-errors', '-module-cache-path', str(root / 'module-cache'),
                str(root / 'main.swift'), str(root / 'Control.swift'), '-o', str(root / 'decoder')],
               cwd=root, env=environment, check=True, timeout=120)
for mode in ('passed', 'failed', 'changed', 'native_first', 'missing_native', 'duplicate', 'invalid_utf8', 'overflow', 'cancelled'):
    case = root / mode
    case.mkdir(mode=0o700)
    result = subprocess.run([str(root / 'decoder'), str(case), mode], cwd=case, env=environment,
                            capture_output=True, timeout=10)
    receipt = case / ('stop-' + mode + '.json')
    if mode in ('duplicate', 'invalid_utf8', 'overflow'):
        assert result.returncode == 5 and not receipt.exists(), (mode, result)
    elif mode == 'missing_native':
        assert result.returncode == 0 and not receipt.exists()
    elif mode == 'cancelled':
        assert result.returncode == 0
        row = json.loads(receipt.read_bytes())
        assert row['status'] == 'cancelled' and 'exit_code' not in row
        assert not (case / ('output-' + mode + '.log')).exists()
    else:
        assert result.returncode == 0, (mode, result)
        row = json.loads(receipt.read_bytes())
        assert row['status'] == ('failed' if mode in ('failed', 'changed') else 'passed')
        assert row['native_state'] == 0 and row['cleanup_verified'] is True
        assert 'stdout_base64' not in row and (case / ('output-' + mode + '.log')).read_bytes() == b'synthetic output\n'
        assert (case / ('control-' + mode + '.log')).read_bytes().startswith(b'CHECK_RESULT ')
print(json.dumps({'fixture_root': str(root), 'field_mutations_refused_per_case': 21, 'lifecycle_cases': 9,
                  'vm_booted': False, 'provider_usage': False}))
