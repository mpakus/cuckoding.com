# Ponytail Plugin (`instruction_skill`)

## Role

Ponytail is an optional instruction skill that pushes agents toward minimal, YAGNI-oriented solutions. It is enabled per role and stage, never globally, and never weakens safety, correctness, accessibility, observability, or trust boundaries.

## Manifest highlights

- `kind: instruction_skill`; detect the upstream skill package at a pinned version, or vendor a reviewed copy with license recorded.
- Permissions: none beyond injection.
- Scopes: role, stage.

## Suggested activation

| Role/stage | Mode |
| --- | --- |
| Specification | Lite or off |
| Implementation | Full |
| Test creation | Lite |
| Security review, accessibility review, incident work | Off |

## Policy overlay

When active, task acceptance criteria, accepted decisions, authentication/isolation/redaction/audit controls, durable state and recovery, tests for critical transitions, accessible alternatives, diagnostic telemetry, and migration obligations remain mandatory. "Simpler" means less accidental complexity within these constraints.

## Evaluation

Compare similar implementation tasks with and without the skill using changed lines, dependencies, review findings, rework, tests, and duration. A smaller unsafe change is a failure.
