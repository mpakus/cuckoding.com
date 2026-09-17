# Long-Running Runs and Power Management

## Goal

A run may last minutes, hours, or days: waiting for provider rate limits, running long test suites, or iterating through several review loops. The laptop will sleep, the lid will close, the network will drop, and the app may be quit or updated in the middle. None of that may corrupt state, duplicate a stage, or silently lose progress.

## Power assertions

- While at least one run is `running` or `waiting` with an active provider session, the Power Manager holds an idle-sleep assertion. Implementation options: `caffeinate -i -w <beam_pid>` supervised as a child process (simple, no native code), or an `IOPMAssertionCreateWithName` call from the shell. Prevent display sleep only if the user enables it.
- `-s` (system sleep prevention) applies only on AC power; on battery with the lid closed macOS will sleep regardless. The UI shows "sleep prevented" / "sleep possible" status and the reason.
- The assertion is released when no run needs it; unattended mode (below) can keep it while a board is active.
- Runs whose next step is a human approval do not hold the assertion.

## Sleep detection and reconciliation

- Compare monotonic time with wall-clock time on every heartbeat tick. On macOS the monotonic clock does not advance during sleep, so a wall-clock jump larger than the tick interval plus tolerance means a sleep gap. Record a `power_events` row with the gap.
- On wake:
  1. Mark all heartbeats inside the gap as `sleep_gap`, not `missed`; do not expire leases for the gap duration.
  2. Inspect every recorded process: alive with matching start identity → continue; gone → adapter recovery (native resume or continuation package).
  3. Probe provider sessions; treat dropped HTTP streams as transient and retry within budget.
  4. Re-probe preview ports and dev servers; restart declared services if they died.
  5. Emit a `run.resumed_after_sleep` event with the gap duration for the timeline.
- The dashboard shows sleep gaps on the run timeline so elapsed time and cost are explainable. Duration metrics store both wall-clock and active (monotonic) time.

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

- Simulated sleep gap: freeze the monotonic clock source in tests, advance wall time, assert reconciliation events.
- Real sleep drill: `pmset sleepnow` during a running stage on a test machine; assert resume, single execution of the stage, and timeline gap.
- Kill the agent process during sleep; assert continuation without duplicate commits.
- Assertion lifecycle: assert `caffeinate`/assertion present only while needed (`pmset -g assertions`).
- Quit with running stages: assert hibernate completes and no orphan process remains.
