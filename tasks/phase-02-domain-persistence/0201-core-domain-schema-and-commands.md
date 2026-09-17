# 0201 — Core Domain Schema and Commands

## Objective

Implement schemas and domain command functions for projects, config versions, boards, workflow versions, role assignments, tasks, dependencies, runs, stage attempts, approvals, findings, environments, processes, agent sessions, and provider accounts as specified in `docs/DB.md`..

## Dependencies

- 0103.

## Scope

Implement schemas and domain command functions for projects, config versions, boards, workflow versions, role assignments, tasks, dependencies, runs, stage attempts, approvals, findings, environments, processes, agent sessions, and provider accounts as specified in `docs/DB.md`.

## Deliverables

- Migrations and Ecto schemas.
- Domain contexts with command functions and guards.
- Constraint tests.

## Checklist

- [ ] Only command functions change state columns.
- [ ] Cycle prevention for dependencies at write time.
- [ ] Role kinds `agent`, `human`, `system` enforced.
- [ ] Ports and environment uniqueness constraints.

## Acceptance criteria

- [ ] All invariants in `docs/DB.md` State integrity hold under property tests.
- [ ] Clean-install and upgrade migrations pass.

## Verification and evidence

Run migration, constraint, and property tests.
