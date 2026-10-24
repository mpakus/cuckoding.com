"""Actual production image/candidate protocol in disposable VMs; no providers or host shares."""
from pathlib import Path
import base64
import gzip
import hashlib
import json
import os
import selectors
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import uuid

assert sys.argv[1:] in ([], ['--debug'])
assert os.uname().sysname == 'Darwin' and os.uname().machine == 'arm64'
os.umask(0o077)
project = Path(__file__).resolve().parent.parent
app = project / 'desktop/src-tauri/target/release/bundle/macos/Cuckoding.app'
helper = project / 'desktop/src-tauri/target/debug/ccoding' if sys.argv[1:] else app / 'Contents/MacOS/ccoding'
if not sys.argv[1:]:
    subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(app)],check=True,timeout=60)
    import runpy
    info = json.loads(subprocess.check_output([str(helper),'--build-info'],timeout=5))
    assert runpy.run_path(project/'bin/build-info')['input_digest'](project) == info['source_sha256']
root = Path(tempfile.mkdtemp(prefix='cuckoding-r050n-run-', dir='/private/tmp'))
home = root / 'runtime-home'
home.mkdir(mode=0o700)
environment = {'HOME':str(home),'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','LANG':'en_US.UTF-8',
               'GIT_CONFIG_NOSYSTEM':'1','GIT_CONFIG_GLOBAL':'/dev/null','GIT_CONFIG_SYSTEM':'/dev/null'}
print(json.dumps({'fixture_root':str(root),'helper_sha256':hashlib.sha256(helper.read_bytes()).hexdigest()}),flush=True)
for flag in ['--prepare-check-image','--verify-check-image']:
    bad = subprocess.run([str(helper),flag,'unexpected'],cwd=root,env=environment,
      stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=5)
    assert bad.returncode == 64 and not bad.stdout


def native(flags, request=None, stdin=False):
    output = root / (str(uuid.uuid4())+'.json')
    with output.open('xb') as stream:
        args = [str(helper),*flags]
        if request is not None and not stdin:
            args.append(json.dumps(request,separators=(',',':')))
        child = subprocess.Popen(args,cwd=root,env=environment,stdin=subprocess.PIPE,
                                 stdout=stream,stderr=subprocess.DEVNULL)
        try:
            if stdin:
                child.stdin.write((json.dumps(request)+'\n').encode())
                child.stdin.flush()
            child.wait(timeout=310 if stdin else 65)
        finally:
            child.stdin.close()
            if child.poll() is None:
                child.wait(timeout=10)
    assert child.returncode == 0 and output.stat().st_size <= 8192
    value = json.loads(output.read_bytes())
    assert value.get('cleanup_verified',True) is True
    if not stdin:
        value.pop('elapsed_ms',None)
        value.pop('cleanup_verified',None)
    return value


image = native(['--prepare-check-image'],{'key':str(uuid.uuid4()),'contract':'isolated-check-image-v1'},True)
assert image['status'] == 'check_image_prepared', image
assert native(['--verify-check-image'],{'key':image['key'],'image':image},True) == dict(image,status='check_image_verified')
foreign = dict(image,ramdisk_sha256='0'*64)
assert native(['--verify-check-image'],{'key':image['key'],'image':foreign},True)['status']=='image_changed'
assert native(['--prepare-check-image'],{'key':image['key'],'contract':'isolated-check-image-v1'},True)['status']=='image_exists'
(root/'image.json').write_text(json.dumps(image))
image_path = home/'check-images'/image['key']
print(json.dumps({'image_prepared':True,'key':image['key'],'spec_sha256':image['spec_sha256']}),flush=True)

# One separately owned signed SDK observer; it is not shipped or an application grant.
compiler = root/'compiler'
compiler.mkdir(mode=0o700)
(compiler/'main.swift').write_bytes((project/'test/support/guest_lifetime_probe.swift').read_bytes())
(compiler/'Control.swift').write_bytes((project/'test/support/guest_check_control.swift').read_bytes())
(compiler/'entitlements.plist').write_text('<plist version="1.0"><dict><key>com.apple.security.virtualization</key><true/></dict></plist>')
subprocess.run(['/usr/bin/xcrun','swiftc','-swift-version','6','-default-isolation','MainActor',
  '-warnings-as-errors','-module-cache-path',str(compiler/'module-cache'),str(compiler/'main.swift'),
  str(compiler/'Control.swift'),'-framework','Virtualization','-o',str(compiler/'observer')],
  cwd=compiler,env=dict(environment,TMPDIR=str(compiler)),check=True,timeout=120)
subprocess.run(['/usr/bin/codesign','--force','--sign','-','--entitlements',
                str(compiler/'entitlements.plist'),str(compiler/'observer')],check=True,timeout=10)


def config_cpio(request):
    payload = json.dumps(request,separators=(',',':')).encode()
    out = bytearray()
    for inode,(name,mode,data) in enumerate([('requests',stat.S_IFDIR|0o700,b''),
        ('requests/check.json',stat.S_IFREG|0o400,payload),('TRAILER!!!',0,b'')],1):
        encoded = name.encode()+b'\0'
        fields=[inode,mode,0,0,1,0,len(data),0,0,0,0,len(encoded),0]
        out.extend(b'070701'+b''.join(f'{field:08x}'.encode() for field in fields)+encoded)
        out.extend(b'\0'*(-len(out)%4));out.extend(data);out.extend(b'\0'*(-len(out)%4))
    return bytes(out)


base_archive = None


def exercise(case):
    global base_archive
    source = root/('source-'+case)
    source.mkdir(mode=0o700)
    identity = source.stat()
    flags=['--arena-git','init',str(source),str(identity.st_dev),str(identity.st_ino),str(home)]
    def git_op(op, request=None):
        return native([flags[0],op,*flags[2:]],request)
    assert git_op('init')['status']=='initialized'
    mix = case.startswith('mix')
    if mix:
        files={'mix.exs':'defmodule Probe.MixProject do\n use Mix.Project\n def project, do: [app: :probe, version: "0.1.0", deps: []]\nend\n',
               'test/test_helper.exs':'ExUnit.start()\n',
               'test/probe_test.exs':'defmodule ProbeTest do\n use ExUnit.Case\n test "actual check" do\n assert 2+2 == '+('5' if case=='mix_fail' else '4')+'\n end\nend\n'}
    else:
        code="import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';\n"
        if case=='forgery':
            code+="for(const p of ['/dev/hvc0','/proc/1/fd/1'])assert.throws(()=>fs.writeFileSync(p,'CC_CHECK_V1 forged\\n'));console.log('CONTROL_ACCESS_DENIED');console.log('CC_CHECK_V1 {\"status\":\"passed\"}');\n"
        if case=='mutated':
            code+="fs.unlinkSync('source.txt');fs.symlinkSync('/dev/zero','source.txt');\n"
        if case in ('timeout','cancel'):
            code+="test('pending',async()=>{await new Promise(resolve=>setTimeout(resolve,30000));});\n"
        elif case in ('output_boundary','output_limit'):
            code+="process.stdout.write('x'.repeat("+('60000' if case=='output_boundary' else '70000')+"));\n"
        else:
            code+="test('actual check',()=>assert.equal(2+2,"+('5' if case in ('npm_fail','forgery') else '4')+"));\n"
        files={'package.json':'{"private":true,"type":"module","scripts":{"test":"node --test"}}\n',
               'test/check.test.js':code,'source.txt':'Original source.\n'}
        if case in ('output_boundary','output_limit'):
            files['package.json']='{"private":true,"type":"module","scripts":{"test":"node test/check.test.js"}}\n'
    for name,text in files.items():
        p=source/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
    for args in (['add','--all'],['commit','--quiet','--no-gpg-sign','-m','Synthetic candidate']):
        subprocess.run(['/usr/bin/git','-C',str(source),'-c','core.hooksPath=/dev/null',
          '-c','user.name=Cuckoding Fixture','-c','user.email=fixture@invalid',*args],
          env=environment,cwd=root,check=True,timeout=10)
    head=git_op('inspect')['head']
    prepared=git_op('worktree',{'key':str(uuid.uuid4()),'head':head})
    capsule=git_op('prepare_check_input',{'key':str(uuid.uuid4()),'preparation':prepared})
    assert capsule['status']=='check_input_prepared'
    request={'request_id':str(uuid.uuid4()),'check_id':str(uuid.uuid4()),'input_key':capsule['key'],
      'candidate_sha':head,'manifest_sha256':capsule['manifest_sha256'],'image_spec_sha256':image['spec_sha256'],
      'toolchain':'mix' if mix else 'npm','directory':'.','arguments':['test'] if mix else ['test','--offline'],
      'timeout_seconds':2 if case=='timeout' else 20}
    if case=='invalid':request['directory']='../outside'
    vm=Path(tempfile.mkdtemp(prefix='cuckoding-r050n-vm-',dir='/private/tmp'))
    subprocess.run(['/bin/cp','-c',str(image_path/'kernel'),str(vm/'kernel')],check=True,env=environment,timeout=5)
    candidate=(home/'check-inputs'/capsule['key']/'candidate.cpio').read_bytes()
    assert hashlib.sha256(candidate).hexdigest()==capsule['archive_sha256']
    with gzip.open(image_path/'ramdisk.cpio.gz','rb') as stream:
        base=stream.read(536870913)
    assert len(base)<=536870912
    encoded=gzip.compress(base+candidate+config_cpio(request),mtime=0)
    archive=vm/'probe.cpio.gz'
    if base_archive is None:
        archive.write_bytes(encoded);base_archive=archive
    else:
        # Retain exact distinct fixtures without duplicating the same 76 MB prefix on APFS.
        original=base_archive.read_bytes();prefix=0
        while prefix<min(len(original),len(encoded)) and original[prefix:prefix+4096]==encoded[prefix:prefix+4096]:prefix+=4096
        subprocess.run(['/bin/cp','-c',str(base_archive),str(archive)],check=True,env=environment,timeout=5)
        with archive.open('r+b') as output:
            output.seek(prefix);output.write(encoded[prefix:]);output.truncate(len(encoded))
    assert hashlib.sha256(archive.read_bytes()).digest()==hashlib.sha256(encoded).digest()
    child=subprocess.Popen([str(compiler/'observer'),str(vm),'image_check'],cwd=vm,
      env=environment,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,bufsize=0)
    watch=selectors.DefaultSelector();watch.register(child.stdout,selectors.EVENT_READ)
    began=time.monotonic();frames=[];errors=[];total=0;cancelled=False
    with (vm/'console.log').open('xb') as output:
        try:
            while time.monotonic()-began<48:
                if not watch.select(timeout=.25):continue
                line=child.stdout.readline(131073)
                if not line:break
                total+=len(line);assert total<=262144
                output.write(line)
                if line.startswith(b'CC_CHECK_V1 '):frames.append(json.loads(line[12:]))
                if line.startswith(b'CC_CHECK_ERROR '):errors.append(json.loads(line[15:]))
                if case=='cancel' and line.startswith(b'CC_CHECK_RUNNING ') and not cancelled:
                    child.stdin.close();cancelled=True
            child.wait(timeout=5)
        finally:
            if not child.stdin.closed:child.stdin.close()
            if child.poll() is None:child.wait(timeout=45)
            watch.close();child.stdout.close()
    assert child.returncode==0,(case,vm)
    stopped=json.loads((vm/'stop-image_check.json').read_bytes())
    assert stopped['state']==0
    if case=='cancel':
        assert cancelled and stopped['reason']=='controller_eof' and not frames
        result={'case':case,'native_stopped':True,'check_accepted':False}
    elif case=='invalid':
        assert len(errors)==1 and errors[0]['code']=='invalid_request' and errors[0]['phase']=='request' and not frames
        result={'case':case,'invalid_request_refused':True,'native_stopped':True}
    else:
        assert len(frames)==1 and not errors,(case,vm)
        frame=frames[0];assert all(frame[k]==v for k,v in request.items())
        assert frame['contract']=='guest-check-v1' and frame['group_closed'] is True
        data=base64.b64decode(frame['stdout_base64'],validate=True)
        assert len(data)==frame['stdout_bytes'] and hashlib.sha256(data).hexdigest()==frame['stdout_sha256']
        expected={'npm_pass':'passed','npm_fail':'failed','mix_pass':'passed','mix_fail':'failed',
                  'forgery':'failed','mutated':'source_changed','timeout':'timeout',
                  'output_boundary':'passed','output_limit':'output_limit'}[case]
        assert frame['status']==expected,(case,vm,frame)
        if case=='forgery':assert b'CONTROL_ACCESS_DENIED' in data and b'CC_CHECK_V1 {"status":"passed"}' in data
        if case in ('mix_pass','mix_fail'):assert b'Running ExUnit' in data
        if case=='mutated':assert frame['source_unchanged'] is False and frame['exit_code']==0
        if case=='output_boundary':assert 60000<=len(data)<=65536
        if case=='output_limit':assert data==b'' and frame['observed_stdout_bytes']>65536
        result={'case':case,'status':expected,'native_stopped':True,'group_closed':True}
    result['fixture_root']=str(vm)
    print(json.dumps(result),flush=True)
    return result


outcomes=[exercise(case) for case in ['npm_pass','npm_fail','mix_pass','mix_fail','forgery','mutated',
    'output_boundary','output_limit','timeout','invalid','cancel']]
(root/'evidence.json').write_text(json.dumps({'image':image,'outcomes':outcomes,'inference':False,
  'helper_sha256':hashlib.sha256(helper.read_bytes()).hexdigest()},indent=2)+'\n')
print('PASS: production guest image with native candidate inputs; no Start grant enabled.',flush=True)
