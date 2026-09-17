# 0103 — Supervision, Leases, and Correlation

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0103-supervision-leases-correlation.md
```

## Objective

Implement the process registry, `DynamicSupervisor` layout from `docs/ARCHITECTURE.md`, leases with TTL and heartbeat (including sleep-gap extension hooks), and correlation propagation through logs and telemetry.

## Dependencies

- 0102.

## Scope

Implement the process registry, `DynamicSupervisor` layout from `docs/ARCHITECTURE.md`, leases with TTL and heartbeat (including sleep-gap extension hooks), and correlation propagation through logs and telemetry.

## Deliverables

- Lease module with acquire, heartbeat, release, expire, extend-for-gap.
- Registry and supervisor tree.
- Telemetry correlation helpers.

## Checklist

- [x] Partial unique index guarantees one active lease per resource.
- [x] Heartbeat gaps flagged as `sleep_gap` when the Power Manager reports one.
- [x] Restart never invents progress.

## Acceptance criteria

- [x] Expired leases are recoverable by a new owner.
- [x] Sleep gaps do not expire leases.

## Verification and evidence

Run lease property tests and a supervisor crash/restart test.
