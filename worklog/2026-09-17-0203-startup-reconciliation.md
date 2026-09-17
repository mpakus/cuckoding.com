# Worklog — 0203 startup reconciliation and recovery

## Metadata

- Date/time (UTC): 2026-09-17T20:42:53Z
- Task: 0203
- Status: done
- Human/agent owner: Codex
- Branch: `feature/0203-startup-reconciliation`
- Start revision: `a64ca2a`
- End revision: task commit
- Environment: Apple Silicon macOS 27.0, Erlang/OTP 28.4, Elixir/Mix 1.19.5

## Intended outcome

Run one guarded reconciliation pass before scheduling on startup and after wake. It must extend sleep-gap leases first, verify recorded PID plus start identity before treating a process as owned, inspect ports and worktrees through replaceable read-only boundaries, recover pending commands, and emit a public continue/recover/block event for every affected run without launching a duplicate stage.

## Acceptance criteria restated

- Never kill, signal, or adopt a process without matching its durable PID and start identity.
- Treat missing resources as recoverable only when ownership is unambiguous; block drift instead of guessing.
- Recover at least 95% of the deterministic interrupted fixtures without manual repair.
- Never start a duplicate stage in crashed, killed, surviving, sleep-gap, port-drift, or worktree-drift fixtures.
- Run the pass before scheduling and preserve an ordered public event for each decision.

## Context inspected

- Required product, architecture, database, workflow, security, execution-environment, and long-running/power documents.
- Task 0203 and the merged task 0202 transition/event foundation at `a64ca2a`.
- Mandatory Ponytail full, local-runner, security-review, Elixir/Phoenix/LiveView, and quality-gates skills.

## Work performed

- Added a read-only `RecoveryInspector` behaviour for PID/start identity, loopback-port owner, and worktree status; the default implementation returns unverified rather than touching the host.
- Added a deterministic reconciler that extends sleep-gap leases before expiry, requeues interrupted command claims, inspects active runs, persists an idempotent continue/recover/block event, and only then dispatches due commands.
- Added a synchronous supervised startup gate immediately after the repository and before the run registry/supervisor.
- Recovery moves the existing run/task/attempt to reconciliation waiting, marks only proven-missing processes lost, and never creates another stage attempt. Identity mismatch, path drift, port conflicts, or unavailable inspection block without changing the process record.
- Added deterministic surviving, crashed/killed, PID-reuse, worktree-drift, port-conflict, unavailable-inspector, sleep-gap, and killed-transaction fixtures.
- Documented reconciliation order, ownership proof, safe blocking, and the Phase 3 implementation boundary.

## Artifacts

- Commits/patches: task commit
- Migrations: none
- Logs/reports/screenshots: this worklog
- Configuration or policy hashes: unchanged; reconciliation reads the run's immutable snapshots

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| Focused reconciler and command tests | pass | Surviving, missing, mismatched, drifted, conflicted, sleep-gap, and killed-transaction fixtures passed; 20/20 generated interrupted fixtures recovered (100%). |
| `rtk mix quality` | pass | 8 properties and 39 tests, 0 failures; warnings-as-errors compile, strict Credo, Sobelow, and dependency audit passed. |
| `rtk env MIX_ENV=test mix ecto.reset` | pass | Rebuilt the disposable database through every migration before full-suite verification. |
| SQLite power-loss fixture | pass | Killed the process holding an open immediate transaction after projection and event inserts; both tables remained empty after connection recovery. |
| Production `release --overwrite` and startup on `CUCKODING_PORT=45786` | pass | `/health` was healthy; RPC showed the reconciler completed with zero unresolved work before the run registry and dynamic supervisor were available; shutdown released the port. |
| XERJ current-project refresh | pass | Current generation committed after the documentation freeze with every code file indexed. |

## Telemetry and operational evidence

- Startup, wake, continue, recover, and block decisions are persisted as public run events with normalized reason atoms only.
- Reconciliation commands use a hash of run state, observed ownership state, outcome, reasons, and cycle ID, so an unchanged pass reuses its result and event.
- Sleep reconciliation records `run.resumed_after_sleep` with the measured gap after leases have been extended.

## Decisions and deviations

- Ponytail full kept one read-only inspector behaviour and deterministic fake instead of implementing the Phase 3 host runner early. Reconciliation classifies and persists state; destructive cleanup remains outside this task.
- XERJ returned the measured PID-plus-start-identity check at `spikes/0004-sleep-wake-power/power_manager_spike.rb:507-510` and Hydra's persisted-agent hydration at `electron/agents/AgentManager.ts:300-351` in pinned revision `d8ad56112c2c3acfb2f65f53b6890f30a25c693c` (MIT). Cuckoding adds durable ownership checks, normalized drift decisions, idempotent events, lease/command ordering, and a synchronous startup gate.
- Due commands dispatch only after every run decision succeeds; a stale or failed decision stops startup instead of allowing scheduling against uncertain ownership.

## Risks and blockers

- The real macOS PID/port/worktree inspector, process termination ladder, and service restart remain Phase 3 runner work. Until then, an active environment with the default unavailable inspector safely blocks.
- Physical sleep/lid-close drills remain supported-platform release evidence; this task covers the deterministic sleep-gap path and killed-transaction recovery.

## Handoff

Proceed to task 0204 for Keychain-backed secret storage and redaction.

## Checklist

- [x] Task acceptance criteria reviewed.
- [x] Relevant documentation updated.
- [x] Tests and checks recorded honestly.
- [x] Secrets and sensitive content excluded/redacted.
- [x] Residual risks and skipped work are explicit.
- [x] Task status and next owner are updated.
