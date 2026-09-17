# 0102 — SQLite Event and Durable Command Foundation

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0102-sqlite-event-command-foundation.md
```

## Objective

Configure Ecto SQLite3 with WAL, foreign keys, busy timeout, and synchronous mode.

## Dependencies

- 0101.

## Scope

Configure Ecto SQLite3 with WAL, foreign keys, busy timeout, and synchronous mode. Implement the append-only `run_events` writer with per-run sequencing, the `commands` table with idempotency keys, and post-commit dispatch.

## Deliverables

- Migration and repo configuration with production pragmas.
- Event writer and command dispatcher modules.
- Property tests for sequencing and idempotency.

## Checklist

- [x] Event and projection written in one transaction.
- [x] Duplicate idempotency key returns the original result.
- [x] Dispatch happens only after commit.
- [x] Bounded retries with `not_before` backoff.

## Acceptance criteria

- [x] Concurrent writers never produce a sequence gap or duplicate.
- [x] Interrupted dispatch is replayed exactly once after restart.

## Verification and evidence

Run persistence tests with production pragmas and a crash-injection test between commit and dispatch.
