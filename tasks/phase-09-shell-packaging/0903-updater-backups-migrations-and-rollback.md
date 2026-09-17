# 0903 — Updater, Backups, Migrations, and Rollback

## Objective

Implement update checks, signature verification, hibernation requirement for schema changes, database and knowledge snapshots, migration execution with progress, health checks, and rollback..

## Dependencies

- 0902.
- 0201.

## Scope

Implement update checks, signature verification, hibernation requirement for schema changes, database and knowledge snapshots, migration execution with progress, health checks, and rollback.

## Deliverables

- Updater integration and tests.

## Checklist

- [ ] Never downgrade onto an incompatible database.
- [ ] Safe mode available.

## Acceptance criteria

- [ ] Update and rollback drill passes.

## Verification and evidence

Run the update/rollback drill on a test machine.
