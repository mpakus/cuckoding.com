# Worklog — 0201 core domain schema and commands

## Metadata

- Date/time (UTC): 2026-09-17T19:59:00Z
- Task: 0201
- Status: done
- Human/agent owner: Codex
- Branch: `feature/0201-core-domain-schema`
- Start revision: `bcd81a5`
- End revision: task commit
- Environment: Apple Silicon macOS 27.0, Erlang/OTP 28.4, Elixir/Mix 1.19.5

## Intended outcome

Add the smallest relational core and guarded context APIs for project configuration, boards/workflows/tasks, run execution, approvals/findings, environments/processes/sessions, and provider accounts. Database constraints must preserve role kinds, dependency acyclicity, active-run/attempt/environment uniqueness, and port ownership under concurrent writes.

## Context inspected

- Required product, architecture, database, workflow, security, and execution-environment documents.
- Task 0201 and the completed Phase 1 persistence/supervision foundation.
- Mandatory Ponytail full, security-review, Elixir/Phoenix/LiveView, workflow-and-kanban, and quality-gates skills.
- Clean `main` at `bcd81a5`; task branch created before edits.

## Work performed

- Added the task 0201 relational core with database checks, foreign keys, version uniqueness, and partial ownership indexes.
- Added UUIDv7 identifiers and narrow context commands whose creation changesets exclude lifecycle state fields.
- Added guarded board/workflow ownership, environment port-range validation, active attempt/environment/port exclusivity, and transactional dependency-cycle rejection.
- Added focused schema, constraint, command-boundary, and dependency property coverage.
- Updated the database, development, and plan documentation with the implemented boundaries and reference-coding provenance.

## Artifacts

- Commits/patches: task commit
- Migrations: `20260917200500_create_core_domain.exs`
- Logs/reports/screenshots: this worklog
- Configuration or policy hashes: workflow snapshots retain their caller-provided content hash; policy snapshots remain task 0202 scope

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| `rtk mix ecto.reset` | pass | Rebuilt the empty development database through every migration after verifying all durable tables contained zero rows. |
| `rtk mix test test/cuckoding/domain_test.exs` | pass | 1 property and 4 focused tests, 0 failures. |
| `rtk mix quality` | pass | 5 properties and 29 tests, 0 failures; warnings-as-errors compile, strict Credo, Sobelow, and dependency audit passed. |
| Clean test migration | pass | Disposable test database migrated from an empty database and ran the focused suite. |
| Production `ecto.migrate` and `release --overwrite` against the retained pre-0201 database | pass | Applied only migration 0201 to the prior schema and assembled the production release. |
| Production release on `CUCKODING_PORT=45784` | pass | `/health` reported healthy database, PubSub, and endpoint state; release RPC confirmed the run registry and dynamic supervisor; shutdown left no listener. |
| XERJ current-project refresh | pass | Generation 12 committed 886 records; all 79 code files indexed with no code junk, and the temporary flood-stage override was restored to `null`. |

## Telemetry and operational evidence

- UUIDv7 defaults, lifecycle defaults, partial ownership constraints, and cycle rejection are exercised by the focused tests.
- Task 0202 remains responsible for transactional lifecycle transitions and their append-only event rows.

## Decisions and deviations

- Ponytail full kept queryable invariants in columns and constraints while deferring state-machine behavior, secret storage, artifact content, and host execution to their assigned tasks.
- Vibe Kanban's Apache-2.0 UUID-backed task record was used as a reference for explicit relational identity only; Cuckoding adds UUIDv7 commands, hierarchy, database checks, DAG validation, immutable snapshots, and partial ownership indexes.

## Risks and blockers

- `tasks.active_run_id` is intentionally not assigned by task 0201 creation commands. Task 0202 must set it only inside the same transaction as the run transition and event because SQLite cannot add the circular task-to-run foreign key after table creation.

## Handoff

Proceed to task 0202 for versioned snapshots, idempotent state transitions, and same-transaction event sequencing.

## Checklist

- [x] Task acceptance criteria reviewed.
- [x] Relevant documentation updated.
- [x] Tests and checks recorded honestly.
- [x] Secrets and sensitive content excluded/redacted.
- [x] Residual risks and skipped work are explicit.
- [x] Task status and next owner are updated.
