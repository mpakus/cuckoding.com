# R100c — Verify database backups before startup migrations

Status: verified and integrated locally, 2026-10-23. Base `872dfa7`.

- [x] Before pending migrations of a recognized existing workspace, create a
  consistent private SQLite copy, verify integrity/FKs/schema, hash and sync it,
  and exclusively retain a dated receipt. Refuse migration on failure; preserve
  incomplete attempts. Fresh/current schemas need no new backup; future schemas
  still refuse. No provider/profile/project copy or automatic restoration.
- [x] Keep startup ownership/readiness ordering and finite limits; do not start
  authentication, HTTP or agent dispatch before backup/migration succeeds.
- [x] Show dated public backup metadata in Settings, with exact scope and location;
  never expose database rows, arbitrary paths or restoration authority.
- [x] Verify prior-schema/WAL preservation, faults/unsafe paths, restart/retained
  copies and packaged upgrade; update docs/AGENTS/README, merge local main and
  delete the feature branch without publication. Full updater/rollback, physical
  power-loss and clean-machine release acceptance remain separate.

[Verification and artifact identity](../worklog/2026-10-23-R100c-upgrade-backups.md).
