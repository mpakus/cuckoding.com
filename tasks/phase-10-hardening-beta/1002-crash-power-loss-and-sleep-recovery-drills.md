# 1002 — Crash, Power-Loss, and Sleep Recovery Drills

## Objective

Run drills: kill -9 during transactions, power loss simulation, real sleep during each default stage, lid close on battery, quit during hibernate; verify single execution, evidence preservation, and timeline gaps.

```yaml
status: complete
owner: codex
started_at: 2026-09-18
completed_at: 2026-09-18
worklog: worklog/2026-09-18-1002-recovery-drills.md
```

## Dependencies

- 0306.
- 0203.

## Scope

Run drills: kill -9 during transactions, power loss simulation, real sleep during each default stage, lid close on battery, quit during hibernate; verify single execution, evidence preservation, and timeline gaps.

## Deliverables

- Drill scripts and results.

## Checklist

- [x] Each default stage survives a real sleep.
- [x] No duplicate commits or PRs.

## Acceptance criteria

- [x] 95% recovery target met across drills.

## Verification and evidence

The committed report records 27/27 passing observations. It includes automated
crash, transaction, restart, quit/hibernate, assertion, and idempotent release
coverage; real sleep for all five default stages; and a battery `Clamshell
Sleep` with exactly-once worker recovery.
