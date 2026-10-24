import fs from 'node:fs';
import crypto from 'node:crypto';

export const environment = Object.freeze({
  HOME: '/tmp/home', PATH: '/opt/elixir/bin:/usr/bin:/bin', LANG: 'C.UTF-8',
  ERL_FLAGS: '+S 2:2 +SDcpu 1 +SDio 1 +A 1', HEX_OFFLINE: '1', MIX_ENV: 'test',
  NPM_CONFIG_CACHE: '/tmp/home/.npm', NPM_CONFIG_AUDIT: 'false',
  NPM_CONFIG_FUND: 'false', NPM_CONFIG_OFFLINE: 'true', RTK_NO_TRACKING: '1'
});
export const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const uuid = value => typeof value === 'string' &&
  /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/.test(value);
const hex = (value, n) => typeof value === 'string' && new RegExp('^[0-9a-f]{' + n + '}$').test(value);
const keys = (value, fields) => value && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('|') === [...fields].sort().join('|');
export function relative(value) {
  return typeof value === 'string' && Buffer.byteLength(value) <= 240 &&
    !/[\\\p{Cc}]/u.test(value) && value.split('/').every(p => p && p !== '.' && p !== '..');
}
export function validateWork(value) {
  if (!keys(value, ['toolchain', 'directory', 'arguments']) ||
      !['npm', 'mix'].includes(value.toolchain) ||
      !(value.directory === '.' || relative(value.directory)) ||
      !Array.isArray(value.arguments) || value.arguments.length > 16 ||
      !value.arguments.every(a => typeof a === 'string' && Buffer.byteLength(a) <= 256 &&
        !/\p{Cc}/u.test(a))) throw Error('invalid_request');
  return value;
}
export function validateRequest(value, image) {
  if (!keys(value, ['request_id', 'check_id', 'input_key', 'candidate_sha', 'manifest_sha256',
    'image_spec_sha256', 'toolchain', 'directory', 'arguments', 'timeout_seconds']) ||
      !uuid(value.request_id) || !uuid(value.check_id) || !uuid(value.input_key) ||
      !hex(value.candidate_sha, 40) || !hex(value.manifest_sha256, 64) ||
      !hex(value.image_spec_sha256, 64) || value.image_spec_sha256 !== image.spec_sha256 ||
      !Number.isInteger(value.timeout_seconds) || value.timeout_seconds < 1 ||
      value.timeout_seconds > 300) throw Error('invalid_request');
  validateWork({toolchain: value.toolchain, directory: value.directory, arguments: value.arguments});
  return value;
}
export function regular(path, maximum, mode) {
  const parts = path.split('/').filter(Boolean);
  let current = '';
  for (const part of parts.slice(0, -1)) {
    current += '/' + part;
    if (!fs.lstatSync(current).isDirectory()) throw Error('source_changed');
  }
  const descriptor = fs.openSync(path, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  try {
    const before = fs.fstatSync(descriptor);
    if (!before.isFile() || before.nlink !== 1 || before.size > maximum ||
        (mode !== undefined && (before.mode & 0o7777) !== mode)) throw Error('source_changed');
    const bytes = fs.readFileSync(descriptor);
    const after = fs.fstatSync(descriptor);
    if (bytes.length !== before.size || before.size !== after.size ||
        before.mtimeMs !== after.mtimeMs || before.ctimeMs !== after.ctimeMs) throw Error('source_changed');
    return bytes;
  } finally {
    fs.closeSync(descriptor);
  }
}
export function validateManifest(value, request) {
  if (!keys(value, ['contract', 'key', 'worktree_key', 'candidate_sha', 'tree_sha', 'files']) ||
      value.contract !== 'candidate-check-input-v1' || value.key !== request.input_key ||
      !uuid(value.worktree_key) || value.candidate_sha !== request.candidate_sha ||
      !hex(value.tree_sha, 40) || !Array.isArray(value.files) || value.files.length > 10000) throw Error('invalid_input');
  const names = new Set();
  let size = 0;
  for (const file of value.files) {
    if (!keys(file, ['path', 'mode', 'bytes', 'sha256']) || !relative(file.path) ||
        file.path.split('/').some(p => p.toLowerCase() === '.git') ||
        names.has(file.path) || !['100644', '100755'].includes(file.mode) ||
        !Number.isInteger(file.bytes) || file.bytes < 0 || file.bytes > 8388608 ||
        !hex(file.sha256, 64)) throw Error('invalid_input');
    names.add(file.path);
    size += file.bytes;
    if (size > 67108864) throw Error('invalid_input');
  }
  return value.files;
}
export function verifyFiles(files) {
  for (const file of files) {
    const bytes = regular('/work/checkout/' + file.path, 8388608, file.mode === '100755' ? 0o755 : 0o644);
    if (bytes.length !== file.bytes || hash(bytes) !== file.sha256) throw Error('source_changed');
  }
}
