# 0501 — Versioned Workflow Engine

## Objective

Implement workflow definition parsing and validation (stages, role kinds, transitions, budgets, knowledge triggers, checkpoint intervals), immutable versions, transition evaluation, gates, and routing of findings..

## Dependencies

- 0405.

## Scope

Implement workflow definition parsing and validation (stages, role kinds, transitions, budgets, knowledge triggers, checkpoint intervals), immutable versions, transition evaluation, gates, and routing of findings.

## Deliverables

- Workflow schema and validator.
- Transition evaluator.
- Property tests.

## Checklist

- [ ] Missing stages, invalid transitions, unsafe cycles, and unknown role kinds rejected.
- [ ] Versions immutable once used.

## Acceptance criteria

- [ ] Default template and a custom template both run through the evaluator.
- [ ] Findings route per transition labels.

## Verification and evidence

Run validator and evaluator property tests.
