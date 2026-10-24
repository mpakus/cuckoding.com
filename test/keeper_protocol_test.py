"""ASan regression of production keeper parsing/private files, without starting a VM."""
from pathlib import Path
import hashlib
import os
import subprocess
import tempfile

assert os.uname().sysname == 'Darwin' and os.uname().machine == 'arm64'
os.umask(0o077)
project=Path(__file__).resolve().parent.parent
root=Path(tempfile.mkdtemp(prefix='cuckoding-keeper-protocol-',dir='/private/tmp'))
print('Fixture:',root,flush=True)
args=['/usr/bin/xcrun','swiftc','-target','arm64-apple-macosx13.0','-swift-version','6',
    '-default-isolation','MainActor','-warnings-as-errors','-D','KEEPER_TESTS','-sanitize=address',
    '-module-cache-path',str(root/'cache'),str(project/'desktop/src-tauri/keeper/main.swift'),
    str(project/'test/support/keeper_protocol_tests.swift'),'-framework','Virtualization','-o',str(root/'tests')]
for command,name,timeout in [(args,'compile.log',120),([str(root/'tests')],'result.log',10)]:
    with (root/name).open('xb') as output:
        result=subprocess.run(command,cwd=root,stdout=output,stderr=subprocess.STDOUT,timeout=timeout)
    if result.returncode:
        print((root/name).read_bytes()[-8192:].decode(errors='replace'))
        raise SystemExit(result.returncode)
print((root/'result.log').read_text().strip())
print('Test binary SHA256:',hashlib.sha256((root/'tests').read_bytes()).hexdigest())
