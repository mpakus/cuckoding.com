# 0203 — Startup Reconciliation and Recovery

## Objective

Implement the reconciliation pass that runs before scheduling on start and after wake: leases, recorded processes (PID plus start identity), ports, worktrees, pending commands.

## Dependencies

- 0202.

## Scope

Implement the reconciliation pass that runs before scheduling on start and after wake: leases, recorded processes (PID plus start identity), ports, worktrees, pending commands. Continue, recover, or block each run with events.

## Deliverables

- Reconciler module and event types.
- Fixtures for crashed, killed, and surviving processes.

## Checklist

- [ ] Never kill or adopt a process without verifying identity.
- [ ] Block runs with unresolved drift instead of guessing.

## Acceptance criteria

- [ ] 95% of interrupted fixtures recover without manual repair.
- [ ] No duplicate stage execution in any fixture.

## Verification and evidence

Run recovery fixtures including power-loss simulation (kill -9 during transaction).
