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
  1. Mark all heartbeats inside the gap as `sleep_gap`, not `missed`; do not expire leases for the gap duration.
  2. Inspect every recorded process: alive with matching start identity → continue; gone → adapter recovery (native resume or continuation package).
  3. Probe provider sessions; treat dropped HTTP streams as transient and retry within budget.
  4. Re-probe preview ports and dev servers; restart declared services if they died.
  5. Emit a `run.resumed_after_sleep` event with the gap duration for the timeline.
- The dashboard shows sleep gaps on the run timeline so elapsed time and cost are explainable. Duration metrics store both wall-clock duration and active uptime duration.

## Checkpoint cadence

- Adapters that support native session persistence checkpoint at stage boundaries and every N minutes of activity (policy `checkpoint_interval_minutes`).
- Adapters without native persistence write a continuation package at the same cadence: task revision, current spec, diff summary, completed checks, open findings, artifact hashes, public handoff.
- Long-running commands (test suites, builds) are launched with timeouts and are resumable only by re-execution; their partial output is kept as an artifact.

## Unattended mode

- A board can be marked unattended for a time window: approvals are queued, notifications are sent (macOS notification through the shell, optional webhook plugin), sleep prevention stays on while the board has queued work, and budget alerts pause the board instead of blocking.
- Unattended mode never bypasses human approval gates; it only keeps the machine awake and the queue moving up to the gate.

## Quit, update, and restart

- Quit offers: hibernate all runs (default), stop all runs, or cancel quit. Hibernate completes checkpoints before the shell terminates the release.
- Schema-changing updates require hibernation; the updater refuses to proceed with running stages.
- On start, reconciliation runs before any scheduling: leases, processes, ports, worktrees, and pending commands.

## Budgets for long runs

- Per-run `max_elapsed_hours` (active time) and `max_wall_hours` are separate; sleep gaps count toward wall time only.
- Budget exhaustion moves the task to `waiting` for approval; the user can extend the budget with an audit event.

## Verification

- Simulated sleep gap: freeze the uptime clock, advance continuous monotonic time, and assert reconciliation events. Advance wall time alone and assert that no gap is inferred.
- Real sleep drill: `pmset sleepnow` during a running stage on a test machine; assert resume, single execution of the stage, and timeline gap.
- Kill the agent process during sleep; assert continuation without duplicate commits.
- Assertion lifecycle: assert `caffeinate`/assertion present only while needed (`pmset -g assertions`).
- Quit with running stages: assert hibernate completes and no orphan process remains.
