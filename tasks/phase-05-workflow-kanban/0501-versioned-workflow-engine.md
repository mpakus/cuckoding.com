# 0501 — Versioned Workflow Engine

## Objective

Implement workflow definition parsing and validation (stages, role kinds, transitions, budgets, knowledge triggers, checkpoint intervals), immutable versions, transition evaluation, gates, and routing of findings..

```yaml
status: done
owner: codex
started_at: 2026-09-17
worklog: worklog/2026-09-17-0501-versioned-workflow-engine.md
```

## Dependencies

- 0405.

## Scope

Implement workflow definition parsing and validation (stages, role kinds, transitions, budgets, knowledge triggers, checkpoint intervals), immutable versions, transition evaluation, gates, and routing of findings.

## Deliverables

- Workflow schema and validator.
- Transition evaluator.
- Property tests.

## Checklist

- [x] Missing stages, invalid transitions, unsafe cycles, and unknown role kinds rejected.
- [x] Versions immutable once used.

## Acceptance criteria

- [x] Default template and a custom template both run through the evaluator.
- [x] Findings route per transition labels.

## Verification and evidence

`test/cuckoding/workflows/definition_test.exs` covers the default and custom templates, gates, all finite budget dimensions, finding routing, invalid definitions, generated unsafe cycles, and generated acyclic flows. The existing database trigger and state-machine regression keep published workflow versions immutable. Exact full-gate evidence is recorded in the linked worklog.
