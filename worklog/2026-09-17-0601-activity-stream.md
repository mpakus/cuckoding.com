# Worklog — 0601 normalized activity event stream

## Metadata

- Date/time (UTC): 2026-09-17
- Task: 0601
- Status: complete
- Human/agent owner: codex
- Branch: `feature/0601-activity-stream`
- Start revision: `dbbd054`
- End revision: pending commit

## Acceptance criteria

- Persist redacted normalized public events with the project → board → task → run → stage attempt → agent-session correlation chain.
- Broadcast only committed event sequences.
- Reconnect from the last acknowledged per-stream sequence without loss or duplication.
- Render sleep gaps and stale/reconciling state in an accessible LiveView activity component.

## Reference coding

- Focused XERJ searches of the project and pinned Vibe Kanban index were attempted first; the configured node at `127.0.0.1:9200` was unreachable, so retrieval is degraded.
- Inspected pinned Vibe Kanban revision `735654971bd396aa97b65166955678e4c34f8bf8` under Apache-2.0. `crates/utils/src/msg_store.rs:37-119` keeps a bounded history and chains it with broadcast delivery, while lagged subscriber messages are logged and dropped.
- Adapted the history-plus-live interface, not its volatile delivery semantics: Cuckoding uses SQLite as the full history, allocates gapless per-stream sequences transactionally, broadcasts only after commit, and catches up after the acknowledged sequence. No peer code was copied.

## Work performed

- Claimed task 0601 and restated its acceptance criteria.
- Added transaction-scoped event collection so both direct event appends and command/approval transactions publish only committed sequence hints; rolled-back rows never broadcast.
- Added recursive redaction and persisted nullable project, board, task, run, stage-attempt, agent-session, role, runtime, model, and request correlation to every public event.
- Added an idempotent normalized adapter-event recorder keyed by a SHA-256 provider-event digest, without persisting the raw external event ID.
- Added bounded ordered catch-up after the acknowledged per-stream sequence, subscribe-before-read connection, recent global activity, freshness/reconciliation classification, and durable-ID deduplication in LiveView.
- Added an accessible activity table with explicit stale/current/reconciling labels and sleep-gap duration text.
- Updated architecture, database, dashboard, development, and implementation-plan documentation.

## Verification

- `rtk mix test test/cuckoding/activity_stream_test.exs test/cuckoding/execution/event_store_test.exs test/cuckoding/state_machine_test.exs test/cuckoding/walking_skeleton_test.exs` — passed: 2 properties and 19 tests, 0 failures. Covers post-commit delivery, post-insert rollback silence, redaction, the full persisted correlation chain, duplicate suppression, reconnect catch-up, stale state, sleep-gap rendering, state transitions, and release-flow compatibility.
- `rtk mix compile --warnings-as-errors` — passed.
- `rtk mix test test/cuckoding/execution/event_store_property_test.exs --repeat-until-failure 5` — six consecutive property runs passed after one earlier full-suite attempt hit a transient SQLite `database is locked` error during concurrent `BEGIN IMMEDIATE`; no code or data assertion failed.
- Final `rtk mix quality` — passed: formatter check; unused dependency check; compiler with warnings as errors; 10 properties and 117 tests with 0 failures; Credo strict over 101 source files and 1,387 modules/functions with no issues; Sobelow clean; Hex audit found no retired or advisory packages.
- `rtk git diff --check` — passed before commit.

## Handoff

Complete. PubSub is deliberately only a wake-up hint; SQLite remains authoritative after browser disconnect, process lag, or reconnect.
