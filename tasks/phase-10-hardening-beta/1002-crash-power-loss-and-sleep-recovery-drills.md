# 1002 — Crash, Power-Loss, and Sleep Recovery Drills

## Objective

Run drills: kill -9 during transactions, power loss simulation, real sleep during each default stage, lid close on battery, quit during hibernate; verify single execution, evidence preservation, and timeline gaps.

```yaml
status: in_progress
owner: codex
started_at: 2026-09-18
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

- [ ] Each default stage survives a real sleep.
- [ ] No duplicate commits or PRs.

## Acceptance criteria

- [ ] 95% recovery target met across drills.

## Verification and evidence

Attach drill logs and process inspections.
