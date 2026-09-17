# 0503 — Multiple Boards, Scheduler, and Unattended Mode

## Objective

Implement board and project concurrency limits, global session limits, fair scheduling with priority/dependencies/age/resource fit, board pause/hibernate, and unattended-mode windows with notifications..

## Dependencies

- 0502.
- 0306.

## Scope

Implement board and project concurrency limits, global session limits, fair scheduling with priority/dependencies/age/resource fit, board pause/hibernate, and unattended-mode windows with notifications.

## Deliverables

- Scheduler module and tests.
- Unattended-mode settings and notifier hook.

## Checklist

- [ ] No board starves another.
- [ ] Scheduler checks ports and memory headroom.
- [ ] Unattended mode queues approvals and holds the assertion only with queued work.

## Acceptance criteria

- [ ] Two boards run concurrently without crossover.
- [ ] Overnight simulation passes.

## Verification and evidence

Run scheduler fairness tests and the unattended simulation.
