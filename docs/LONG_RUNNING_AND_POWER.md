# Long-Running Runs and Power Management

## Goal

A run may last minutes, hours, or days: waiting for provider rate limits, running long test suites, or iterating through several review loops. The laptop will sleep, the lid will close, the network will drop, and the app may be quit or updated in the middle. None of that may corrupt state, duplicate a stage, or silently lose progress.

## Power assertions

- While at least one run is `running` or `waiting` with an active provider session, the Power Manager holds an idle-sleep assertion through a supervised `caffeinate -i -w <beam_pid>`. The Power Manager explicitly stops `caffeinate` when no run needs the assertion; `-w` also releases it if BEAM exits. Prevent display sleep only if the user enables it.
- `-s` (system sleep prevention) applies only on AC power; on battery with the lid closed macOS will sleep regardless. The UI shows "sleep prevented" / "sleep possible" status and the reason.
- The assertion is released when no run needs it; unattended mode (below) can keep it while a board is active.
- Runs whose next step is a human approval do not hold the assertion.

## Sleep detection and reconciliation

- Sample `CLOCK_MONOTONIC` and `CLOCK_UPTIME_RAW` on every heartbeat tick. On macOS 27, monotonic time continues during sleep while uptime does not. A continuous-minus-uptime divergence above the one-second tolerance is a sleep gap; record the measured divergence in a `power_events` row. Keep wall time only for UTC event timestamps and wall-duration reporting so an NTP or manual clock change cannot forge a sleep gap.
- On wake:
  1. Call `Cuckoding.Execution.Leases.extend_for_sleep_gap/2` before expiry reconciliation. It extends only leases that were alive when the measured gap began and emits a correlated heartbeat telemetry event with `kind: sleep_gap`; do not classify the gap as missed heartbeats.
  2. Inspect every recorded process: alive with matching start identity → continue; gone → adapter recovery (native resume or continuation package).
  3. Probe provider sessions; treat dropped HTTP streams as transient and retry within budget.
  4. Re-probe preview ports and dev servers; restart declared services if they died.
  5. Emit a `run.resumed_after_sleep` event with the gap duration for the timeline.
- The dashboard shows sleep gaps on the run timeline so elapsed time and cost are explainable. Duration metrics store both wall-clock duration and active uptime duration.

## Checkpoint cadence

- The design target is checkpointing at stage boundaries and periodically where
  an adapter supports it. Executable workflow snapshots use
  `checkpoint_interval_ms`; `checkpoint_interval_minutes` in example policy YAML
  is not a guarantee of a live periodic provider checkpoint.
- Control/lifecycle paths persist supported checkpoints or bounded continuation
  data. Resuming a provider session depends on its adapter, retained session and
  verified ownership. Missing workers/checkpoints require explicit recovery.
- Long-running commands (test suites, builds) are launched with timeouts and are resumable only by re-execution; their partial output is kept as an artifact.

## Unattended mode

- A board can be marked unattended for a time window: approvals are queued, notifications are sent (macOS notification through the shell, optional webhook plugin), sleep prevention stays on while the board has queued work, and budget alerts pause the board instead of blocking.
- Unattended mode never bypasses human approval gates; it only keeps the machine awake and the queue moving up to the gate.

The latest trusted project policy may disable unattended mode or cap `unattended.max_window_hours`; the default cap is 12 hours. Pending approvals inside an active window are returned through the scheduler's notifier behaviour with a stable key derived from the approval ID. Expired windows produce neither notifier work nor a power-assertion reason. Notification delivery never decides an approval.

## Quit, update, and restart

- The implemented shell Quit path asks the host shutdown policy to pause
  admission and hibernate active runs before terminating the release. A failed
  hibernation blocks shutdown; this is not a three-choice quit dialog. Explicit
  Stop all is a separate dashboard control.
- Schema-changing updates require hibernation; the updater refuses to proceed with running stages.
- On start, reconciliation runs before any scheduling: leases, processes, ports, worktrees, and pending commands.

The startup reconciler blocks supervisor startup until one pass completes. It extends sleep-gap leases before expiry, returns interrupted command claims to `pending`, inspects every active run, persists one idempotent continue/recover/block decision and public event, then dispatches due commands. The inspection boundary is read-only: it can report PID start identity, loopback-port ownership, and worktree status, but it cannot signal, adopt, delete, or rewrite a host resource. A live PID with a different start identity, an unknown port owner, worktree drift, or an unavailable inspector blocks the run. Missing owned resources move the run and task to `waiting` with reason `reconciliation`; recovery services added in Phase 3 resume the existing attempt rather than creating a duplicate.

The implemented `Cuckoding.Power.Manager` uses the task 0004 clock contract through a sterile Ruby probe because BEAM does not expose `CLOCK_UPTIME_RAW`. Each sample returns continuous and uptime milliseconds from one process. A divergence strictly above the configured one-second tolerance writes `sleep_gap`, then calls `Execution.Reconciler` with the power-event ID as its stable cycle ID; the reconciler extends leases before expiry and writes per-run `run.resumed_after_sleep` events. `wake_reconciled` is written only after that pass succeeds. A failed pass retains and retries the same cycle rather than recording another gap or losing the wake work.

The manager starts and stops a scrubbed `caffeinate -i -w <beam-pid>` child after verifying its PID/start identity. Eligible provider sessions hold it unless the run is waiting on a pending human approval. A durable, unexpired unattended board window may also hold it while the board has active or queued work, but the manager never decides or mutates an approval. The test environment starts the manager disabled and exercises it through explicit injected clock ticks.

Successful `wake_reconciled` metadata records `extended_leases` and
`expired_leases` as integer counts from the reconciler. A regression exercises
the real reconciler through the power manager so test doubles cannot mask a
count/list contract mismatch.

## Budgets for long runs

Executable stage budgets use `max_attempts`, `active_ms`, `wall_ms`, `tokens`
and `cost_micros`. The executor checks recorded attempt/timing/usage totals and
passes the stage wall timeout to the runner. Reported token/cost data may arrive
after execution; unavailable usage is not proof of unused budget.

Exhaustion in the delivery executor fails the stage and blocks the run; a linked
board batch enters Needs attention. It does not automatically open an
extend-budget approval or rewrite the frozen policy. The hour-based policy
examples describe intended configuration, not a separate implemented override UI.

## Board execution recovery

The durable board claim survives Pause, Needs attention and pending controls.
The shared dispatcher reloads SQLite before admitting work and the shared
resource gate waits while wake reconciliation is pending. An idle controller
has no provider process; decision sessions use the normal owned process path.

Resume rechecks authorization, policy, Git ownership and task requests. A missing
orchestration worker cannot be assumed resumable: inspect retained evidence and
use explicit Retry/Skip/Stop after verified cleanup. Pending control outcomes
keep admission closed. Workspace Resume does not silently resume a separately
paused board. See [CUCKODING-CONTROL.md](CUCKODING-CONTROL.md). Full autonomous
Tauri-shell restart remains a separate acceptance gate.

Prepared autonomous goals add a narrower automatic path: a classified, known-ended
stage can persist a recovery checkpoint and backoff, then resume through the shared
dispatcher after restart. The host verifies ended processes, retained worktree and
unchanged authorization before claiming that checkpoint once. Completed stage
evidence is reused; failure retries, provider waits and productive continuations
have separate counters within the same cumulative goal deadline. Unknown prompt
outcomes or unverified ownership still require attention. This does not change
historical fixed-batch recovery.

Task 1057 exercised physical sleep on the current native Tauri build with real
Codex delivery. Its empty-project goal completed two tasks and nine criteria
after 12 measured gaps totaling 202,608 ms; each gap had a durable successful wake
event, delivery stages were not duplicated, and the single Run authorization was
unchanged. The existing fresh-VM restart sample covers a known-ended checkpoint;
it is not an in-flight Tauri restart test. See the
[task worklog](../worklog/2026-09-30-1057-autonomous-project-flow.md) for exact
provider, build, process and result evidence.

## Verification

- Simulated sleep gap: freeze the uptime clock, advance continuous monotonic time, and assert reconciliation events. Advance wall time alone and assert that no gap is inferred.
- Real sleep drill: `pmset sleepnow` during a running stage on a test machine; assert resume, single execution of the stage, and timeline gap.
- Kill the agent process during sleep; assert continuation without duplicate commits.
- Assertion lifecycle: assert `caffeinate`/assertion present only while needed (`pmset -g assertions`).
- Quit with running stages: assert hibernate completes and no orphan process remains.
