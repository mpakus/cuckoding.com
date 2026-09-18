# 0503 — Multiple Boards, Scheduler, and Unattended Mode

## Objective

Implement board and project concurrency limits, global session limits, fair scheduling with priority/dependencies/age/resource fit, board pause/hibernate, and unattended-mode windows with notifications.

```yaml
status: done
owner: codex
started_at: 2026-09-17
worklog: worklog/2026-09-17-0503-board-scheduler.md
```

## Dependencies

- 0502.
- 0306.

## Scope

Implement board and project concurrency limits, global session limits, fair scheduling with priority/dependencies/age/resource fit, board pause/hibernate, and unattended-mode windows with notifications.

## Deliverables

- Scheduler module and tests.
- Unattended-mode settings and notifier hook.

## Checklist

- [x] No board starves another.
- [x] Scheduler checks ports and memory headroom.
- [x] Unattended mode queues approvals and holds the assertion only with queued work.

## Acceptance criteria

- [x] Two boards run concurrently without crossover.
- [x] Overnight simulation passes.

## Verification and evidence

`test/cuckoding/execution/scheduler_test.exs` covers independent two-board admission, durable fairness rotation, dependencies, board/project/global capacity, port and memory headroom, board-scoped hibernation, unattended approval notifications, policy window limits, and assertion release on expiry. Exact commands and results are recorded in the linked worklog.
