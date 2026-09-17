# 0103 — Supervision, Leases, and Correlation

## Objective

Implement the process registry, `DynamicSupervisor` layout from `docs/ARCHITECTURE.md`, leases with TTL and heartbeat (including sleep-gap extension hooks), and correlation propagation through logs and telemetry..

## Dependencies

- 0102.

## Scope

Implement the process registry, `DynamicSupervisor` layout from `docs/ARCHITECTURE.md`, leases with TTL and heartbeat (including sleep-gap extension hooks), and correlation propagation through logs and telemetry.

## Deliverables

- Lease module with acquire, heartbeat, release, expire, extend-for-gap.
- Registry and supervisor tree.
- Telemetry correlation helpers.

## Checklist

- [ ] Partial unique index guarantees one active lease per resource.
- [ ] Heartbeat gaps flagged as `sleep_gap` when the Power Manager reports one.
- [ ] Restart never invents progress.

## Acceptance criteria

- [ ] Expired leases are recoverable by a new owner.
- [ ] Sleep gaps do not expire leases.

## Verification and evidence

Run lease property tests and a supervisor crash/restart test.
