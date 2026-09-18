# 0903 — Updater, Backups, Migrations, and Rollback

## Objective

Implement update checks, signature verification, hibernation requirement for schema changes, database and knowledge snapshots, migration execution with progress, health checks, and rollback..

```yaml
status: complete
owner: codex
started_at: 2026-09-18
worklog: worklog/2026-09-18-0903-updater-backups-rollback.md
```

## Dependencies

- 0902.
- 0201.

## Scope

Implement update checks, signature verification, hibernation requirement for schema changes, database and knowledge snapshots, migration execution with progress, health checks, and rollback.

## Deliverables

- Updater integration and tests.

## Checklist

- [x] Never downgrade onto an incompatible database.
- [x] Safe mode available.

## Acceptance criteria

- [x] Update and rollback drill passes.

## Verification and evidence

Run the update/rollback drill on a test machine.
