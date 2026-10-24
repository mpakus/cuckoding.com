import fs from 'node:fs';
import {spawn, execFileSync} from 'node:child_process';
import {performance} from 'node:perf_hooks';
import {environment, hash, regular, validateRequest, validateManifest, verifyFiles} from '/protocol.mjs';

const group = '/sys/fs/cgroup/work/';
let request;
let output;
let phase = 'request';
try {
  if (process.getuid() !== 0 || fs.readdirSync('/sys/class/net').some(n => n !== 'lo')) throw Error('invalid_environment');
  const image = JSON.parse(regular('/image.json', 8192, 0o444));
  request = validateRequest(JSON.parse(regular('/requests/check.json', 8192, 0o400)), image);
  phase = 'manifest';
  const manifest = regular('/requests/candidate.json', 5242880, 0o444);
  if (hash(manifest) !== request.manifest_sha256) throw Error('invalid_input');
  const files = validateManifest(JSON.parse(manifest), request);
  phase = 'source';
  verifyFiles(files);
  phase = 'versions';
  // Fixed image programs only; no project cwd, startup environment or package code.
  if (process.versions.node !== '24.22.1' ||
      (request.toolchain === 'npm' && execFileSync('/usr/bin/npm', ['--version'], {cwd: '/', env: environment, timeout: 5000, maxBuffer: 1024}).toString().trim() !== '11.12.1') ||
      (request.toolchain === 'mix' && execFileSync('/opt/elixir/bin/elixir', ['-e', 'IO.write(System.version() <> "|" <> String.trim(File.read!(Path.join([:code.root_dir(), "releases", "28", "OTP_VERSION"]))))'],
        {cwd: '/', env: environment, timeout: 15000, maxBuffer: 1024}).toString() !== '1.20.3|28.5.0.8')) throw Error('unsupported_version');
  phase = 'directory';
  const directory = '/work/checkout' + (request.directory === '.' ? '' : '/' + request.directory);
  let parent = '';
  for (const part of directory.split('/').filter(Boolean)) {
    parent += '/' + part;
    if (!fs.lstatSync(parent).isDirectory()) throw Error('invalid_input');
  }
  output = fs.openSync('/run/check/output', 'wx', 0o600);
  phase = 'launch';
  let status;
  const began = performance.now();
  const child = spawn('/bin/sh', ['/launch'], {cwd: '/', env: environment, stdio: ['pipe', output, output]});
  child.stdin.on('error', () => {});
  child.stdin.end(JSON.stringify({toolchain: request.toolchain, directory: request.directory, arguments: request.arguments}));
  process.stdout.write('CC_CHECK_RUNNING ' + JSON.stringify({request_id:request.request_id, check_id:request.check_id}) + '\n');
  const timer = setInterval(() => {
    if (performance.now() - began >= request.timeout_seconds * 1000) status = 'timeout';
    else if (fs.fstatSync(output).size > 65536) status = 'output_limit';
    if (status) fs.writeFileSync(group + 'cgroup.kill', '1');
  }, 25);
  const code = await new Promise(resolve => {
    child.once('error', () => resolve(null));
    child.once('close', value => resolve(value));
  });
  clearInterval(timer);
  phase = 'collect';
  fs.writeFileSync(group + 'cgroup.kill', '1');
  for (let n = 0; n < 100 && !/^populated 0$/m.test(fs.readFileSync(group + 'cgroup.events', 'utf8')); n++)
    await new Promise(resolve => setTimeout(resolve, 10));
  if (!/^populated 0$/m.test(fs.readFileSync(group + 'cgroup.events', 'utf8'))) throw Error('cleanup_uncertain');
  let unchanged = true;
  try { verifyFiles(files); } catch { unchanged = false; }
  const size = fs.fstatSync(output).size;
  fs.closeSync(output);
  output = undefined;
  const bytes = size <= 65536 ? regular('/run/check/output', 65536, 0o600) : Buffer.alloc(0);
  if (size > 65536) status = 'output_limit';
  else if (!unchanged) status = 'source_changed';
  else status ??= code === 0 ? 'passed' : 'failed';
  const result = {...request, contract: 'guest-check-v1', status, source_unchanged: unchanged,
    group_closed: true, stdout_bytes: bytes.length, observed_stdout_bytes:size, stdout_sha256: hash(bytes),
    stdout_base64: bytes.toString('base64')};
  if (Number.isInteger(code) && code >= 0 && code <= 255) result.exit_code = code;
  process.stdout.write('CC_CHECK_V1 ' + JSON.stringify(result) + '\n');
} catch (error) {
  try { fs.writeFileSync(group + 'cgroup.kill', '1'); } catch {}
  process.stdout.write('CC_CHECK_ERROR ' + JSON.stringify({phase, detail:
    ['ETIMEDOUT','ENOENT','EACCES','ERR_CHILD_PROCESS_STDIO_MAXBUFFER'].includes(error.code) ? error.code : null,
    code: ['invalid_request', 'invalid_input',
    'source_changed', 'unsupported_version', 'cleanup_uncertain', 'invalid_environment'].includes(error.message) ?
    error.message : 'control_failed'}) + '\n');
} finally {
  if (output !== undefined) fs.closeSync(output);
}
