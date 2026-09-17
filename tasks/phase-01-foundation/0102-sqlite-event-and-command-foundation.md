# 0102 — SQLite Event and Durable Command Foundation

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

- [ ] Event and projection written in one transaction.
- [ ] Duplicate idempotency key returns the original result.
- [ ] Dispatch happens only after commit.
- [ ] Bounded retries with `not_before` backoff.

## Acceptance criteria

- [ ] Concurrent writers never produce a sequence gap or duplicate.
- [ ] Interrupted dispatch is replayed exactly once after restart.

## Verification and evidence

Run persistence tests with production pragmas and a crash-injection test between commit and dispatch.
