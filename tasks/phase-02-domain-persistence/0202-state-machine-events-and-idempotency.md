# 0202 — State Machine, Events, and Idempotency

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

- [ ] No transition without an event.
- [ ] `waiting` carries a reason.
- [ ] Active and wall durations tracked separately.

## Acceptance criteria

- [ ] Invalid transitions are rejected with an explicit outcome.
- [ ] A replayed command is a no-op with the original result.

## Verification and evidence

Run state machine property tests and event ordering tests.
