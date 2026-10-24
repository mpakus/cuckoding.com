import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {validateRequest, validateManifest, validateWork, relative, regular, hash, environment}
  from '../desktop/src-tauri/src/check_image/protocol.mjs';

const image = {spec_sha256: 'a'.repeat(64)};
const request = {request_id: '00000000-0000-4000-8000-000000000001',
  check_id: '00000000-0000-4000-8000-000000000002', input_key: '00000000-0000-4000-8000-000000000003',
  candidate_sha: 'b'.repeat(40), manifest_sha256: 'c'.repeat(64), image_spec_sha256: image.spec_sha256,
  toolchain: 'npm', directory: '.', arguments: ['test', '--offline'], timeout_seconds: 30};
test('closed check request rejects foreign bindings, tools, types, paths and command injection', () => {
  assert.equal(validateRequest(request, image), request);
  for (const [field, value] of [['extra', true], ['request_id', '../escape'], ['check_id', null],
    ['input_key', false], ['candidate_sha', 'b'.repeat(39)], ['manifest_sha256', 'A'.repeat(64)],
    ['image_spec_sha256', 'd'.repeat(64)], ['toolchain', '/bin/sh'], ['directory', '../../root'],
    ['arguments', ['test', '\u0085']], ['arguments', Array(17).fill('x')],
    ['timeout_seconds', 0], ['timeout_seconds', 301], ['timeout_seconds', '30']]) {
    assert.throws(() => validateRequest({...request, [field]: value}, image), field);
  }
  for (const value of ['', '/', 'a//b', 'a/../b', 'a\\b', 'a\nb', '\u0085']) assert.equal(relative(value), false);
  assert.equal(relative('directory with space/файл'), true);
  assert.throws(() => validateWork({toolchain:'npm', arguments:[], directory:'.', binary:'/bin/sh'}));
  assert(Object.isFrozen(environment));
  assert.equal(environment.NPM_CONFIG_OFFLINE, 'true');
});
test('candidate manifest is exact metadata, never policy or arbitrary filesystem authority', () => {
  const file = {path:'src/a', mode:'100644', bytes:3, sha256:hash(Buffer.from('abc'))};
  const manifest = {contract:'candidate-check-input-v1', key:request.input_key, worktree_key:request.request_id,
    candidate_sha:request.candidate_sha, tree_sha:'d'.repeat(40), files:[file]};
  assert.deepEqual(validateManifest(manifest, request), [file]);
  for (const changed of [{...manifest,key:request.request_id}, {...manifest,candidate_sha:'e'.repeat(40)},
    {...manifest,files:[file,file]}, {...manifest,files:[{...file,path:'../x'}]},
    {...manifest,files:[{...file,path:'.git/config'}]}, {...manifest,files:[{...file,mode:'120777'}]},
    {...manifest,files:[{...file,bytes:8388609}]}, {...manifest,policy:'allow all'}]) {
    assert.throws(() => validateManifest(changed, request));
  }
});
test('bounded source reads refuse changed modes, aliases and indirect files', () => {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(),'cuckoding-image-protocol-')));
  const file = path.join(root,'file');
  fs.writeFileSync(file, 'abc', {mode:0o644});
  assert.equal(regular(file,3,0o644).toString(),'abc');
  assert.throws(() => regular(file,2));
  fs.symlinkSync(file,path.join(root,'symlink'));
  assert.throws(() => regular(path.join(root,'symlink'),3));
  fs.linkSync(file,path.join(root,'hardlink'));
  assert.throws(() => regular(file,3));
  fs.unlinkSync(path.join(root,'hardlink'));
  fs.chmodSync(file,0o755);
  assert.throws(() => regular(file,3,0o644));
  fs.mkdirSync(path.join(root,'dir'));
  fs.symlinkSync(path.join(root,'dir'),path.join(root,'alias'));
  fs.writeFileSync(path.join(root,'dir','child'),'abc');
  assert.throws(() => regular(path.join(root,'alias','child'),3));
});
