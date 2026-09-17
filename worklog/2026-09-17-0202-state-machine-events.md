# Worklog — 0202 state machine, events, and idempotency

## Metadata

- Date/time (UTC): 2026-09-17T20:27:58Z
- Task: 0202
- Status: done
- Human/agent owner: Codex
- Branch: `feature/0202-state-machine-events`
- Start revision: `72a3554`
- End revision: task commit
- Environment: Apple Silicon macOS 27.0, Erlang/OTP 28.4, Elixir/Mix 1.19.5

## Intended outcome

Implement explicit task and run transition commands from `docs/FLOW.md`. Every accepted transition must append a public, strictly ordered run event in the same immediate transaction; waiting must retain a reason; stage timing must keep active and wall duration separate; and replaying a stable command key must return the original result without repeating the transition.

## Acceptance criteria restated

- Invalid task and run transitions return an explicit rejected outcome and do not change durable state.
- Every accepted transition writes exactly one event atomically with the state update.
- Waiting transitions require a reason, and active versus wall duration remains independently recorded.
- Replaying an already completed idempotent command returns its original result and emits no duplicate event.
- Property coverage exercises every declared state and allowed transition, plus event ordering.

## Context inspected

- Required product, architecture, database, workflow, security, and execution-environment documents.
- Task 0202 and the completed task 0201 schema/command foundation at `72a3554`.
- Mandatory Ponytail full, workflow-and-kanban, security-review, Elixir/Phoenix/LiveView, and quality-gates skills.

## Work performed

- Added explicit task and run transition graphs, required wait reasons, and property coverage for every declared and undeclared state pair.
- Added transactional transition commands that persist one idempotent command outcome and, for every accepted state change, update the projection and append one ordered public event atomically.
- Synchronized active run transitions with their owning task and kept standalone pre/post-run task transitions on a namespaced event stream.
- Added idempotent stage timing updates with separate cumulative active and wall milliseconds.
- Made published workflow and project-config versions immutable and changed run creation to snapshot the board's workflow plus ordered roles while requiring a trusted same-project policy version.
- Published the exact transition graph and command/event behavior in the database, flow, development, and plan documentation.

## Artifacts

- Commits/patches: task commit
- Migrations: `20260917202800_add_state_machine_guards.exs`
- Logs/reports/screenshots: this worklog
- Configuration or policy hashes: run rows retain the trusted project-config version ID and an immutable workflow/role snapshot

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| Focused task 0202 and regression tests | pass | 4 properties and 15 tests, 0 failures; covers state pairs, ordered events, wait reasons, replay, timing, snapshots, and existing event/command behavior. |
| `rtk mix quality` | pass | 7 properties and 33 tests, 0 failures; warnings-as-errors compile, strict Credo, Sobelow, and dependency audit passed. |
| `rtk env MIX_ENV=test mix ecto.reset` | pass | Rebuilt the disposable database through every migration, including task 0202. |
| Data-bearing forward migration copy | pass | A temporary task-0201 schema with one project, config version, and workflow version retained all `1/1/1` rows, added `runs.wait_reason`, passed `PRAGMA foreign_key_check`, and installed all four immutability triggers. |
| Production migration and `release --overwrite` | pass | Applied only migration 0202 to the retained prior production database and assembled the release. |
| Production release on `CUCKODING_PORT=45785` | pass | `/health` reported healthy database, PubSub, and endpoint state; release RPC confirmed both run supervisors; shutdown left no listener. |
| XERJ current-project refresh | pass | Current generation committed after the documentation freeze with every code file indexed. |

## Telemetry and operational evidence

- Accepted task/run transitions emit `task.transitioned` or `run.transitioned`; timing updates emit `stage.timing_recorded`.
- Public command results carry the outcome, reason or transition, event ID, and event sequence without provider payloads or credentials.
- Rejected transitions persist a public result but do not emit an event because no state changed.

## Decisions and deviations

- Ponytail full reused the existing command ledger and event allocator instead of adding another dispatcher or workflow abstraction. Task 0501 remains responsible for parsing arbitrary versioned workflow definitions.
- XERJ returned Vibe Kanban's explicit closed `TaskStatus` enum at `crates/db/src/models/task.rs:7-20` in pinned revision `735654971bd396aa97b65166955678e4c34f8bf8` (Apache-2.0). Cuckoding adapts the explicit vocabulary and adds guarded graphs, atomic event projections, idempotent outcomes, wait reasons, and timing.
- Standalone task transitions use `task:<uuid>` as their append-only stream key; active-run transitions use the run UUID and update the owning task in the same transaction.

## Risks and blockers

- Timing collection remains a runner/adapter responsibility; this task provides the idempotent durable command that records already measured monotonic-active and continuous-wall deltas.
- Workflow YAML parsing, arbitrary stage routing, and gate evaluation remain assigned to task 0501.

## Handoff

Proceed to task 0203 for startup reconciliation of durable run, attempt, environment, process, session, lease, and command state.

## Checklist

- [x] Task acceptance criteria reviewed.
- [x] Relevant documentation updated.
- [x] Tests and checks recorded honestly.
- [x] Secrets and sensitive content excluded/redacted.
- [x] Residual risks and skipped work are explicit.
- [x] Task status and next owner are updated.
