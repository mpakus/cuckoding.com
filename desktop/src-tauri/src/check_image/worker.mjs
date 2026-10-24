import fs from 'node:fs';
import {spawnSync} from 'node:child_process';
import {validateWork, environment} from '/protocol.mjs';

try {
  const status = fs.readFileSync('/proc/self/status', 'utf8');
  if (process.getuid() !== 1000 || process.getgid() !== 1000 ||
      !/^NoNewPrivs:\s+1$/m.test(status) || !/^CapEff:\s+0000000000000000$/m.test(status) ||
      fs.readFileSync('/proc/self/cgroup', 'utf8') !== '0::/work\n') throw Error();
  const input = fs.readFileSync(0);
  if (input.length > 8192) throw Error();
  const work = validateWork(JSON.parse(input));
  const child = spawnSync(work.toolchain === 'npm' ? '/usr/bin/npm' : '/opt/elixir/bin/mix',
    work.arguments, {cwd: '/work/checkout' + (work.directory === '.' ? '' : '/' + work.directory),
      env: environment, stdio: ['ignore', 1, 2]});
  process.exit(child.status ?? 125);
} catch {
  process.exit(125);
}
