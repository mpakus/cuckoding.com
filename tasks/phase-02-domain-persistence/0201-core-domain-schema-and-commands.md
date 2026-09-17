# 0201 — Core Domain Schema and Commands

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0201-core-domain-schema.md
```

## Objective

Implement schemas and domain command functions for projects, config versions, boards, workflow versions, role assignments, tasks, dependencies, runs, stage attempts, approvals, findings, environments, processes, agent sessions, and provider accounts as specified in `docs/DB.md`.

## Dependencies

- 0103.

## Scope

Implement schemas and domain command functions for projects, config versions, boards, workflow versions, role assignments, tasks, dependencies, runs, stage attempts, approvals, findings, environments, processes, agent sessions, and provider accounts as specified in `docs/DB.md`.

## Deliverables

- Migrations and Ecto schemas.
- Domain contexts with command functions and guards.
- Constraint tests.

## Checklist

- [x] Only command functions change state columns.
- [x] Cycle prevention for dependencies at write time.
- [x] Role kinds `agent`, `human`, `system` enforced.
- [x] Ports and environment uniqueness constraints.

## Acceptance criteria

- [x] All implemented task 0201 invariants in `docs/DB.md` State integrity hold under property tests.
- [x] Clean-install and upgrade migrations pass.

## Verification and evidence

Run migration, constraint, and property tests.
