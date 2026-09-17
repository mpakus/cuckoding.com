# Worklog — 0103 supervision, leases, and correlation

## Metadata

- Date/time (UTC): 2026-09-17T19:45:00Z
- Task: 0103
- Status: done
- Human/agent owner: Codex
- Branch: `feature/0103-supervision-leases-correlation`
- Start revision: `aa10e84`
- End revision: task commit
- Environment: Apple Silicon macOS 27.0, Erlang/OTP 28.4, Elixir/Mix 1.19.5

## Intended outcome

Add the smallest durable lease API, process registry and dynamic run-supervisor layout, sleep-gap extension hook, and correlation propagation helpers. Expired resources must be reclaimable, reported sleep must extend active leases before expiry is evaluated, and supervised worker restarts must recover from durable inputs rather than invent progress.

## Context inspected

- Required product, architecture, database, workflow, security, and execution-environment documents.
- Task 0103 and the completed SQLite/event/command foundation from task 0102.
- Mandatory Ponytail full, local-runner, security-review, Elixir/Phoenix/LiveView, and quality-gates skills.
- Clean `main` at `aa10e84`; task branch created before edits.

## Work performed

- Added the forward `leases` migration with validated identifiers, SHA-256 token hashes, acquisition/heartbeat/expiry/release timestamps, release consistency checks, expiry/owner indexes, and a partial unique index for one unreleased lease per resource.
- Added the lease API for acquire, authenticated heartbeat, idempotent release, expiry, active lookup, and sleep-gap extension. Acquisition closes an expired row and inserts its successor inside the same immediate SQLite transaction; only a freshly generated high-entropy bearer token leaves the API, while SQLite stores its fixed-length hash.
- Added correlated lease telemetry. A reported sleep gap extends only leases that were alive at gap start and emits the heartbeat event with `kind: sleep_gap` before normal expiry reconciliation.
- Added `Cuckoding.Correlation` helpers for Logger context capture/restore and telemetry metadata. The existing request plug now sets correlation context through this single boundary.
- Added the unique run registry, root dynamic run supervisor, and one registered supervisor per run. Per-run child specs carry durable identifiers; a supervisor crash rebuilds workers from SQLite-backed inputs instead of restoring mutated process memory.
- Added property, persistence, security-boundary, telemetry, process-context, and crash/restart regression coverage and synchronized architecture, database, power, development, plan, and task documentation.

## Artifacts

- Commits/patches: task commit on `feature/0103-supervision-leases-correlation`
- Migrations: `20260917195000_create_leases.exs`
- Logs/reports/screenshots: production health and live Registry/DynamicSupervisor PID check captured in the task transcript; no tokens or secrets persisted
- Configuration or policy hashes: no policy or dependency version changes; OTP `:crypto`, Registry, DynamicSupervisor, Logger, and `:telemetry` are existing platform/runtime facilities

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| Focused Task 0103 tests | pass | Lease reclaim and sleep-gap properties, token authorization, idempotent release, stale heartbeat closure, sleep telemetry, correlation propagation, partial-index structure, and run-supervisor crash recovery passed. |
| `rtk mix quality` | pass | Formatter, unused-lock check, warnings-as-errors compiler, 4 properties plus 25 tests, strict Credo, Sobelow, and Hex audit passed; Credo found no issues. |
| Empty-table migration rebuild | pass | Verified the unreleased development `leases` table contained zero rows, rolled back only migration 0103, and reapplied its final inline constraints without data loss. |
| `rtk env MIX_ENV=test mix ecto.reset` followed by `rtk mix test` | pass | Rebuilt the disposable database through both forward migrations and passed all 4 properties plus 25 tests. |
| Production `ecto.migrate` and `release --overwrite` against the task 0102 temporary database | pass | Applied only migration 0103 to the prior schema and assembled the production release. |
| Production release on `CUCKODING_PORT=45783` | pass | `/health` returned healthy database/PubSub/endpoint state; release RPC confirmed live `RunRegistry` and `RunSupervisors` processes; shutdown left no listener. |
| XERJ project and peer retrieval | pass | Inspected Hydra's persisted-agent hydration at `electron/agents/AgentManager.ts:300-346` in pinned MIT revision `d8ad56112c2c3acfb2f65f53b6890f30a25c693c` before implementation. |
| Final `cuckoding-project-v7` autoindex refresh | pass | Current generation committed after documentation freeze; all code files indexed. |

## Telemetry and operational evidence

- Property checks exercised 30 randomized lease-expiry/reacquisition cases and 20 randomized sleep-gap extensions per suite run. These are correctness checks, not throughput measurements.
- Lease lifecycle and sleep-gap events carry counts plus public resource/correlation identifiers. Raw bearer tokens are absent from schemas, Logger metadata, telemetry, and test output.

## Decisions and deviations

- Ponytail full applied: the task uses OTP Registry, DynamicSupervisor, Logger, `:telemetry`, `:crypto`, and existing Ecto facilities, with no new dependency or polling process.
- Hydra's persisted-agent hydration informed the restart rule only. Cuckoding uses SQLite as the durable source of truth and reconstructs a worker from its recorded lease identifier instead of copying Hydra's in-memory map.
- Sleep-gap extension deliberately precedes expiry. Leases already expired before the measured gap began are not revived.

## Risks and blockers

- A sleep gap is emitted as correlated telemetry in this foundation; durable `power_events` timeline rows belong to the Power Manager implementation. The hook and ordering contract are now explicit and tested.
- If the root `RunSupervisors` process itself crashes, its dynamic child inventory is lost and must be rebuilt by startup reconciliation in task 0203. Individual per-run supervisors restart automatically from their durable identifiers.

## Handoff

Task 0103 completes the Phase 1 foundation and is ready to fast-forward into `main`. Task 0201 can build core domain tables and commands on the event, command, lease, correlation, and supervision primitives without adding host process behavior early.

## Checklist

- [x] Task acceptance criteria reviewed.
- [x] Relevant documentation updated.
- [x] Tests and checks recorded honestly.
- [x] Secrets and sensitive content excluded/redacted.
- [x] Residual risks and skipped work are explicit.
- [x] Task status and next owner are updated.
