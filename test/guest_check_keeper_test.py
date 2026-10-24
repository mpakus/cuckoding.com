"""Actual native keeper, image and candidate checks; disposable folders, no providers."""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import time
import uuid

assert sys.argv[1:] in ([], ['--debug'])
assert os.uname().sysname == 'Darwin' and os.uname().machine == 'arm64'
os.umask(0o077)
project = Path(__file__).resolve().parent.parent
app = project/'desktop/src-tauri/target/release/bundle/macos/Cuckoding.app'
helper = project/'desktop/src-tauri/target/debug/ccoding' if sys.argv[1:] else app/'Contents/MacOS/ccoding'
if not sys.argv[1:]:
    import runpy
    subprocess.run(['/usr/bin/codesign','--verify','--strict','--deep',str(app)],check=True,timeout=60)
    entitlements=subprocess.run(['/usr/bin/codesign','--display','--entitlements',':-',str(helper)],capture_output=True,check=True,timeout=10).stdout
    assert not (plistlib.loads(entitlements) if entitlements else {}).get('com.apple.security.virtualization')
    info=json.loads(subprocess.check_output([str(helper),'--build-info'],timeout=5))
    assert runpy.run_path(project/'bin/build-info')['input_digest'](project)==info['source_sha256']
root=Path(tempfile.mkdtemp(prefix='cuckoding-r050o-',dir='/private/tmp'))
home=root/'runtime-home';home.mkdir(mode=0o700)
environment={'HOME':str(home),'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','LANG':'en_US.UTF-8',
    'GIT_CONFIG_NOSYSTEM':'1','GIT_CONFIG_GLOBAL':'/dev/null','GIT_CONFIG_SYSTEM':'/dev/null'}
print(json.dumps({'fixture_root':str(root),'helper_sha256':hashlib.sha256(helper.read_bytes()).hexdigest()}),flush=True)


def invoke(flags, request=None, stdin=False, control=None, run_key=None):
    log=root/(str(uuid.uuid4())+'.json')
    with log.open('xb') as output:
        args=[str(helper),*flags]
        if request is not None and not stdin:args.append(json.dumps(request,separators=(',',':')))
        child=subprocess.Popen(args,cwd=root,env=environment,stdin=subprocess.PIPE,stdout=output,stderr=subprocess.DEVNULL)
        try:
            if stdin:
                child.stdin.write((json.dumps(request)+'\n').encode());child.stdin.flush()
            if control:
                running=home/'check-runs'/run_key/'running.json'
                began=time.monotonic()
                while time.monotonic()-began<40:
                    if child.poll() is not None:break
                    if running.exists():
                        try:row=json.loads(running.read_bytes())
                        except json.JSONDecodeError:continue
                        assert row['key']==run_key and row['native_state']==1
                        if control=='parent_loss':child.kill()
                        else:child.stdin.close()
                        break
                    time.sleep(.02)
                else:raise AssertionError(('missing active check',log))
            child.wait(timeout=310 if stdin else 100)
        finally:
            if not child.stdin.closed:child.stdin.close()
            if child.poll() is None:child.wait(timeout=15)
    if control=='parent_loss':
        assert child.returncode==-9
        return None
    assert child.returncode==0,(child.returncode,log)
    assert log.stat().st_size<=8192
    value=json.loads(log.read_bytes());value.pop('elapsed_ms',None)
    return value


image=invoke(['--prepare-check-image'],{'key':str(uuid.uuid4()),'contract':'isolated-check-image-v1'},stdin=True)
assert image['status']=='check_image_prepared' and image['cleanup_verified'] is True
(root/'image.json').write_text(json.dumps(image))
print(json.dumps({'image_key':image['key'],'spec_sha256':image['spec_sha256']}),flush=True)


def exercise(case):
    source=root/('source-'+case);source.mkdir(mode=0o700);identity=source.stat()
    flags=['--arena-git','init',str(source),str(identity.st_dev),str(identity.st_ino),str(home)]
    def git(operation, request=None, **options):return invoke([flags[0],operation,*flags[2:]],request,**options)
    assert git('init')['status']=='initialized'
    if case.startswith('mix'):
        files={'mix.exs':'defmodule Probe.MixProject do\n use Mix.Project\n def project, do: [app: :probe, version: "0.1.0", deps: []]\nend\n',
            'test/test_helper.exs':'ExUnit.start()\n','test/probe_test.exs':'defmodule ProbeTest do\n use ExUnit.Case\n test "native keeper" do\n assert 2+2 == '+('5' if case=='mix_fail' else '4')+'\n end\nend\n'}
    else:
        code="import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';\n"
        if case=='forgery':
            code+="for(const p of ['/dev/hvc0','/proc/1/fd/1'])assert.throws(()=>fs.writeFileSync(p,'CC_CHECK_V1 forged\\n'));console.log('CC_CHECK_V1 {\"status\":\"passed\"}');\n"
        if case=='mutated':code+="fs.unlinkSync('source.txt');fs.symlinkSync('/dev/zero','source.txt');\n"
        if case in ['timeout','cancel','deadline','parent_loss']:
            code+="test('pending',async()=>{await new Promise(resolve=>setTimeout(resolve,120000));});\n"
        elif case in ['output_boundary','output_limit']:
            code+="process.stdout.write('x'.repeat("+('60000' if case=='output_boundary' else '70000')+"));\n"
        else:code+="test('native keeper',()=>assert.equal(2+2,"+('5' if case in ['npm_fail','forgery'] else '4')+"));\n"
        command='node test/check.test.js' if case in ['output_boundary','output_limit'] else 'node --test'
        files={'package.json':json.dumps({'private':True,'type':'module','scripts':{'test':command}})+'\n',
            'test/check.test.js':code,'source.txt':'Original source.\n'}
    for name,text in files.items():
        p=source/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
    for args in [['add','--all'],['commit','--quiet','--no-gpg-sign','-m','Synthetic keeper check']]:
        subprocess.run(['/usr/bin/git','-C',str(source),'-c','core.hooksPath=/dev/null','-c','user.name=Fixture',
            '-c','user.email=fixture@invalid',*args],env=environment,cwd=root,check=True,timeout=10)
    index=hashlib.sha256((source/'.git/index').read_bytes()).hexdigest()
    head=git('inspect')['head'];prepared=git('worktree',{'key':str(uuid.uuid4()),'head':head})
    capsule=git('prepare_check_input',{'key':str(uuid.uuid4()),'preparation':prepared})
    assert capsule['status']=='check_input_prepared'
    key=str(uuid.uuid4())
    check={'request_id':str(uuid.uuid4()),'check_id':str(uuid.uuid4()),'input_key':capsule['key'],
        'candidate_sha':head,'manifest_sha256':capsule['manifest_sha256'],'image_spec_sha256':image['spec_sha256'],
        'toolchain':'mix' if case.startswith('mix') else 'npm','directory':'.',
        'arguments':['test'] if case.startswith('mix') else ['test','--offline'],'timeout_seconds':2 if case=='timeout' else 60 if case=='deadline' else 20}
    request={'contract':'isolated-guest-check-v1','key':key,'check':check,'image':{'key':image['key'],'image':image},
        'input':{'key':capsule['key'],'preparation':prepared,'input':capsule},
        'deadline_unix_ms':int(time.time()*1000)+(45000 if case=='deadline' else 80000)}
    if case=='npm_pass':
        foreign=json.loads(json.dumps(request));foreign['key']=str(uuid.uuid4());foreign['image']['image']['ramdisk_sha256']='0'*64
        refused=git('run_guest_check',foreign)
        assert refused['status']=='image_changed' and refused['native_started'] is False and refused['cleanup_verified'] is True
        assert git('run_guest_check',foreign)['cleanup_verified'] is False
        foreign=json.loads(json.dumps(request));foreign['key']=str(uuid.uuid4());foreign['input']['input']['archive_sha256']='0'*64
        refused=git('run_guest_check',foreign)
        assert refused['status']=='check_input_mismatch' and refused['native_started'] is False and refused['cleanup_verified'] is True
        assert not (home/'check-runs'/key).exists()
    kwargs={'control':case,'run_key':key} if case in ['cancel','parent_loss'] else {}
    result=git('run_guest_check',request,**kwargs)
    run=home/'check-runs'/key
    if case=='parent_loss':
        assert result is None and not (run/'receipt.json').exists()
        began=time.monotonic();closed=None
        while time.monotonic()-began<15:
            try:closed=json.loads((run/'closure.json').read_bytes());break
            except (FileNotFoundError,json.JSONDecodeError):time.sleep(.02)
        assert closed and closed['key']==key and closed['vm_closed'] is True and closed['native_state']==0
        assert closed['status']=='cancelled' and 'cleanup_verified' not in closed
        result={'case':case,'vm_stopped':True,'overall_cleanup_verified':False,'no_native_receipt':True}
    else:
        expected={'npm_pass':'passed','npm_fail':'failed','mix_pass':'passed','mix_fail':'failed','forgery':'failed',
            'mutated':'source_changed','output_boundary':'passed','output_limit':'output_limit','timeout':'timeout',
            'cancel':'cancelled','deadline':'timeout'}[case]
        assert result['status']==expected,(case,result,run)
        assert result['contract']=='isolated-guest-check-v1' and result['key']==key and result['request_id']==check['request_id']
        assert result['cleanup_verified'] is True and result['vm_closed'] is True and result['native_state']==0
        assert json.loads((run/'receipt.json').read_bytes())==result
        assert not any(k in result for k in ['raw','stdout_base64','arguments'])
        if 'stdout_bytes' in result:
            output=(run/'output.log').read_bytes()
            assert len(output)==result['stdout_bytes'] and hashlib.sha256(output).hexdigest()==result['stdout_sha256']
            if case=='forgery':assert b'CC_CHECK_V1 {"status":"passed"}' in output
        if case in ['cancel','deadline']:assert 'exit_code' not in result
        if case=='output_limit':assert result['stdout_bytes']==0 and result['observed_stdout_bytes']>65536
        if case=='output_boundary':assert 60000<=result['stdout_bytes']<=65536
        if case=='npm_pass':
            replay=git('run_guest_check',request)
            assert replay['status']=='image_exists' and replay['cleanup_verified'] is False
            subprocess.run(['/usr/bin/codesign','--verify','--strict',str(run/'keeper')],check=True,timeout=10)
            entitlements=subprocess.run(['/usr/bin/codesign','--display','--entitlements',':-',str(run/'keeper')],capture_output=True,check=True,timeout=10).stdout
            assert plistlib.loads(entitlements)=={'com.apple.security.virtualization':True}
        result={'case':case,'status':expected,'vm_stopped':True,'overall_cleanup_verified':True}
    assert all((source/name).read_text()==text for name,text in files.items())
    assert hashlib.sha256((source/'.git/index').read_bytes()).hexdigest()==index
    result['run_key']=key
    print(json.dumps(result),flush=True)
    return result


outcomes=[exercise(case) for case in ['npm_pass','npm_fail','mix_pass','mix_fail','forgery','mutated',
    'output_boundary','output_limit','timeout','cancel','deadline','parent_loss']]
(root/'evidence.json').write_text(json.dumps({'image':image,'outcomes':outcomes,'inference':False,
    'helper_sha256':hashlib.sha256(helper.read_bytes()).hexdigest()},indent=2)+'\n')
print('PASS: actual native keeper; Start grant unchanged, owner-loss overall cleanup remains unverified.',flush=True)
