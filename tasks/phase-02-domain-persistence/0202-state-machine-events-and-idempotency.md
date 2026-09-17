# 0202 — State Machine, Events, and Idempotency

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0202-state-machine-events.md
```

## Objective

Implement the task and run state machine from `docs/FLOW.md` with transition guards, event emission, wait reasons, active/wall time accounting, and idempotent command handling..

## Dependencies

- 0201.

## Scope

Implement the task and run state machine from `docs/FLOW.md` with transition guards, event emission, wait reasons, active/wall time accounting, and idempotent command handling.

## Deliverables

- Transition table and guard implementation.
- Event types and public summaries.
- Property tests for every state and transition.

## Checklist

- [x] No accepted transition without an event.
- [x] `waiting` carries a reason.
- [x] Active and wall durations tracked separately.

## Acceptance criteria

- [x] Invalid transitions are rejected with an explicit outcome.
- [x] A replayed command is a no-op with the original result.

## Verification and evidence

Run state machine property tests and event ordering tests.
