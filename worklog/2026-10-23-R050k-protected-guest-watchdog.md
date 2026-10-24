# R050k — Protected guest worker watchdog

Completed prerequisite probe on `feature/R050k-protected-guest-watchdog`, base
`5921ad9`; local integration only. The full beta objective remains active.
Previous goal turn made progress: R050j observed native stop and explicitly
retained owner loss as unverified. The full toolchain prerequisite still needs
protected worker budgets/watchdog and ownership before production integration.

Ponytail full5.3.2 MIT; local-runner, security, architecture, quality and Swift
guidance. Reuse the pinned isolated guest and probe; no new app language,
entitlement, guest installation, credential/provider, project or user data grant.
RTK proxy retains exact source/protocol output. Keep `Untitled.md.age` unread.

The actual pinned kernel exposes cgroup v2 PID/memory/CPU support. The official
kernel cgroup-v2 documentation is the reference for hierarchy inheritance,
nondelegated controls, cgroup.kill and populated observations. The installed
Alpine image contains BusyBox su/setpriv; verify actual no-new-privileges and
capability/UID observations before treating that launch path as working.

## Implemented and observed

The existing opt-in probe gains a closed `--watchdog` variant. It reuses the
pinned official Alpine inputs, bounded fresh private setup, two virtual CPUs,
512MiB and no network/storage/socket/host-share devices. The only new Swift code
is in the disposable test helper. No production image, entitlement, language,
native operation, dependency, schema, app grant or mandatory setup step changes.

Root PID1 mounts a nondelegated cgroup v2 hierarchy. A trusted root launcher
joins `/work` before dropping to UID/GID1000 with BusyBox su/setpriv and
no-new-privileges. Worker effective/permitted/inheritable/ambient capability
sets are observed as zero. Root owns policy/scripts and stays outside the worker
group. The worker cannot signal PID1, modify its PID limit or migrate out.
Session-changing descendants retain `/work` membership. The actual guest kernel
enforces the configured 32-task, 64MiB memory, zero-swap and half-core CPU budget.

Fixed adverse workloads attempt eighty sleep children with a busy loop, or a
128MiB write into guest RAM. The root's independent eight-second loop remains
responsive outside those limits, records counters and writes cgroup.kill. It
requires a zero-live-member observation before powering off. Native guest-stop
delegation separately checks explicit Stopped state and retains an exclusive
observation. A surviving keeper observes client EOF but lets the independent
guest deadline close work. Hard keeper SIGTERM still has no accepted stop proof.

The [kernel cgroup-v2 documentation](https://docs.kernel.org/admin-guide/cgroup-v2.html)
supplies the hierarchy/control/kill interface. Reads of the actual configured
kernel and actual probe results, rather than PID polling or group assumptions,
supply the local enforcement observations. Nondelegated controls and distinct
identities matter: a private-copy root-worker mutation modifies limits/migrates
and is correctly rejected even though the VM later shuts down normally.

All guest output remains **diagnostic test evidence**, not trusted completion or
control data. There is no privileged production transport yet. An arbitrary
worker could print forged messages; the fixed probes do not authorize a future
parser to trust them. Only the native SDK writes its separate host observation,
and neither observation is a current SQLite battle receipt or execution grant.
No cleanup is inferred for keeper death or physical sleep.

## Actual verification

- `rtk proxy python3 -B test/guest_lifetime_probe.py --watchdog`: final **four
  cases passed** at `/private/tmp/cuckoding-r050k-cnx313kr`;
  `.ccoding/r050k-watchdog-verified.log`, per-mode logs, native observations and
  `evidence.json`. Controller-loss observation is required for the EOF case.
- `rtk proxy python3 -B test/guest_lifetime_probe.py`: original **five cases
  passed** at `/private/tmp/cuckoding-r050j-898nh9om`;
  `.ccoding/r050k-original-cases.log`. Native input/EOF/deadline/paused-stop
  behavior and missing-proof owner-loss behavior remain intact.
- Each invocation performs strict Swift6/default-main-actor/warnings-as-errors
  compilation and strict signature verification on its private ad-hoc binary.
- Updated helper Address Sanitizer build and canonical-path refusal pass with
  zero diagnostics; `.ccoding/r050k-asan.log`. No VM launches for that check.
- The in-memory launcher mutation removes su/no-new-privileges and runs the
  fixed worker as guest root. The real first case fails on observed policy and
  migration escape. Private fixture `/private/tmp/cuckoding-r050k-11lhu4wz`
  retains the failed log/native shutdown; repository sources never changed.
- Python AST/syntax, local doc targets, whitespace, tested Swift-source hash and
  original application input-digest equality pass. The sealed R100d app remains
  unchanged. No full Elixir/Rust/application build is claimed for this test/docs
  slice; nine actual guest cases are current evidence, not historical counts.

Final protected cases:

| Case | Actual evidence |
| --- | --- |
| PID/CPU pressure | 8.332s native guest shutdown; PID peak32, one cap refusal, 80 throttling periods, empty group |
| Memory pressure | 8.252s native guest shutdown; one group OOM, four killed tasks, empty group |
| Client EOF | 8.332s independent guest shutdown; controller_lost, PID peak32, 80 throttling periods, empty group |
| Abrupt keeper death | 0.204s stream/owned-leader observation; no stop receipt, **cleanup unverified** |

The memory peak is 67,108,864 bytes in the final memory case. The configured
limit is not a claim that every kernel allocation has a universal exact ceiling;
retain the kernel interface's documented semantics. PID/group-empty observations
are kernel data, not a parent/PID-absence heuristic. Each owned probe child was
waited/reaped; this does not independently close an unknown VM after keeper loss.

Earlier successful protection runs remain at
`/private/tmp/cuckoding-r050k-ij8c0nv0` and
`/private/tmp/cuckoding-r050k-vc_6xmaf`; final CPU/session/EOF assertions were
verified in the final fixture above. Current final artifact hashes:

- Kernel `256d5fff4bb892edcb9218c1e6353e388bc3646e65f76c2bc9d958b635d1b00e`.
- RAM filesystem `7368500440832c0732f71ceec2deb4e354626a49fe3157174ec3ef32f61caf29`.
- Swift source `b7c6d3309cfb05fd3e60610abc457c50072a2d935c6153fa03bb8102de6d649f`.
- Probe binary `8b63cdc2fe88accb8349f6d5e0cb75365978d40b2972c37a61a01ea1cac237c0`.

Repeated SDK compilation reduced temporary space to 3.02GiB. After verifying all
exact owned compiler/probe leaders were terminal, only regenerable module caches
in the explicitly recorded R050j/k fixture roots were removed. All other retained
file metadata and final evidence hashes stayed unchanged. Inputs, source, logs,
receipts, binaries and failed fixtures remain. The final ASan cache was removed
after its test; free space is 4.64GiB. No unrelated file or actual user data was
read/deleted to gain space. `Untitled.md.age` stays unread/unstaged.

## Remaining end state

This completes the protected-worker prerequisite under fixed known adverse
workloads. It does not enable Mix/npm, select a shipping VM installer or establish
full arbitrary-workload/sleep/keeper-loss recovery. Next: separate privileged
control and worker output, exact immutable candidate/toolchain transport, bound
native ownership/receipts and supervised OTP admission/settlement, actual toolchain
checks and release/license/platform acceptance. R050i's shipping NPROC=0 stays.
Real-provider, dashboards/ten-minute human flow and signed release gates also
remain in PLAN. No provider call, user workspace/profile, push or publication.
