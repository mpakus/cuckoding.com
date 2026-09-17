# Worklog — 0102 SQLite event and command foundation

## Metadata

- Date/time (UTC): 2026-09-17T19:22:19Z
- Task: 0102
- Status: done
- Human/agent owner: Codex
- Branch: `feature/0102-sqlite-command-foundation`
- Start revision: `6d9a836`
- End revision: task commit
- Environment: Apple Silicon macOS 27.0, Erlang/OTP 28.4, Elixir/Mix 1.19.5

## Intended outcome

Add the smallest durable SQLite foundation: verified WAL/foreign-key/busy-timeout/synchronous pragmas, forward migration for strictly sequenced append-only run events and idempotent commands, atomic event/projection writes, post-commit dispatch, and bounded retry scheduling. Concurrent event writers must not create sequence gaps or duplicates, and a command committed before an interruption must replay once through the same idempotency key.

## Context inspected

- Required product, architecture, database, workflow, security, and execution-environment documents.
- Task 0102 and the completed task 0101 application foundation.
- Mandatory Ponytail full, Elixir/Phoenix/LiveView, security-review, and quality-gates skills.
- Clean `main` at `6d9a836`; task branch created before edits.

## Work performed

- Added Ecto SQL and the SQLite3 adapter with exact dependency pins. Every connection enables WAL, foreign keys, synchronous `NORMAL`, a 5-second busy timeout, and immediate write transactions; development, test, and production databases have explicit paths and bounded pools.
- Added the initial forward migration for the command ledger, append-only run events, and a per-run sequence allocator. Column checks constrain states, attempts, and positive sequences; database triggers reject event updates and deletes.
- Added `EventStore.append/3`, which allocates the next sequence and commits the projection plus event in one immediate transaction. A projection or event failure rolls the entire transaction back.
- Added idempotent command insertion, post-commit dispatch, transactional claims, stable handler idempotency keys, bounded exponential retry scheduling, and a one-shot startup recovery pass. Terminal rows retain their result or a deliberately lossy failure label; arbitrary handler details are never persisted.
- Added SQLite pragma, atomicity, append-only, idempotency, retry, crash-window, interrupted-claim, and concurrent writer property tests. Concurrent property writers use independent committed SQLite connections rather than rollback-only sandbox transactions.
- Added database dependency health and synchronized the database, development, plan, task, and reference-coding documentation with the implemented boundary.

## Artifacts

- Commits/patches: task commit on `feature/0102-sqlite-command-foundation`
- Migrations: `20260917192219_create_event_and_command_foundation.exs`
- Logs/reports/screenshots: production pragma output and release health/status responses captured in the task transcript; no secrets persisted
- Configuration or policy hashes: exact Ecto SQL 3.14.0, Ecto SQLite3 0.24.1, and StreamData 1.4.0 pins recorded in `mix.exs` and `mix.lock`

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| `rtk mix deps.get` | pass | Resolved the exact persistence and property-test pins and updated `mix.lock`. |
| `rtk mix ecto.migrate` | pass | Applied the initial forward migration after replacing unsupported SQLite `ALTER TABLE ADD CONSTRAINT` operations with inline column checks. The failed first attempt rolled back without leaving partial application tables. |
| Focused persistence tests | pass | SQLite pragmas, projection rollback, append-only triggers, idempotency, retry timing, failure-detail redaction, post-commit crash replay, interrupted-claim recovery, and committed concurrent writers passed. |
| `rtk env MIX_ENV=test mix ecto.reset` followed by `rtk mix test` | pass | Rebuilt the disposable test database from an empty prior schema and passed the full suite. |
| `rtk mix quality` | pass | Formatter, unused-lock check, warnings-as-errors compiler, full test suite, strict Credo, Sobelow, and Hex audit passed; Credo found no issues. |
| Production `ecto.create`, `ecto.migrate`, `assets.deploy`, and `release --overwrite` against a temporary database | pass | The release built from the production dependency set and the migration applied cleanly. |
| Live production Repo pragma query | pass | `journal_mode=wal`, `foreign_keys=1`, `synchronous=1` (`NORMAL`), and configured busy timeout `5000` ms. Exqlite installs the timeout through SQLite's native busy handler rather than `PRAGMA busy_timeout`. |
| Production release on `CUCKODING_PORT=45782` | pass | `/health` and `/status` returned healthy database, PubSub, and endpoint state; the endpoint reported only `127.0.0.1`; the release stopped and left no listener. |
| XERJ project and peer retrieval | pass | Inspected Agetor's cited SQLite setup at pinned MIT revision `eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a` and the official Ecto SQLite3 adapter options before implementation. |
| Final `cuckoding-project-v7` autoindex refresh | pass | Current generation committed after documentation freeze; all code files indexed. |

## Telemetry and operational evidence

- Ten randomized committed-concurrency runs covered two to eight writers against the same run sequence. This is correctness evidence, not a throughput benchmark.
- The production release reported database health through an actual `SELECT 1`; no external telemetry or cost data was produced.

## Decisions and deviations

- Ponytail full applied: task 0102 does not introduce Phase 2 domain entities, a polling worker, or Phase 3 process supervision.
- Agetor's WAL, synchronous `NORMAL`, and foreign-key pattern was adapted through official Ecto adapter configuration. Cuckoding adds immediate transactions, the busy handler, checks, append-only triggers, sequence allocation, and its own command semantics.
- Replay is exactly once inside the command ledger. A handler receives the stable idempotency key, but external side effects must honor it because no local database can atomically commit an unrelated external service's result.

## Risks and blockers

- Startup recovery is wired and tested. Continuous wakeup for commands whose `not_before` is still in the future belongs to the later reconciliation/supervision tasks; task 0102 intentionally avoids adding a polling worker early.
- The first migration is a clean-install schema; there was no released prior data schema to transform. The disposable test database was rebuilt from empty and the production migration was exercised separately.

## Handoff

Task 0102 is complete and ready to fast-forward into `main`. Task 0103 should build supervision, leases, and correlation on these durable primitives without turning in-memory workers into sources of truth.

## Checklist

- [x] Task acceptance criteria reviewed.
- [x] Relevant documentation updated.
- [x] Tests and checks recorded honestly.
- [x] Secrets and sensitive content excluded/redacted.
- [x] Residual risks and skipped work are explicit.
- [x] Task status and next owner are updated.
