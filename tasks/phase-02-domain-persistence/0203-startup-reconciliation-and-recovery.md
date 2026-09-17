# 0203 — Startup Reconciliation and Recovery

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0203-startup-reconciliation.md
```

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

- [x] Never kill or adopt a process without verifying identity.
- [x] Block runs with unresolved drift instead of guessing.

## Acceptance criteria

- [x] 95% of interrupted fixtures recover without manual repair.
- [x] No duplicate stage execution in any fixture.

## Verification and evidence

Run recovery fixtures including power-loss simulation (kill -9 during transaction).
