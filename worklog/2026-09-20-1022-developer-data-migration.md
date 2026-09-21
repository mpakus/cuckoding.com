# Worklog — 1022 developer data migration

## Metadata

- Date/time (local): 2026-09-20
- Task: 1022
- Status: complete
- Human/agent owner: codex
- Branch: `fix/1022-local-data-migration`
- Start revision: `34e2d97`
- End revision: task commit

## Acceptance criteria

- Preserve the existing local application data before migration.
- Apply the two pending forward migrations without fabricating updater state.
- Verify database integrity, schema currency, and retained row counts.
- Document the supported distinction between developer replacement builds and signed updates.
- Test the documentation change, launch the verified bundle, merge, and push the result to `main`.

## Context and security review

- The installed database is idle, passes `PRAGMA integrity_check`, and contains
  one project with no active runs or update attempts.
- Applied migrations stop at `20260918024500`; board task intake
  (`20260919090000`) and shared authorization (`20260920170000`) are pending.
- No project `.cuckoding` knowledge or configuration files exist to snapshot.
- The release guard correctly requires updater snapshot state. This local
  developer replacement is instead protected by an explicit, private SQLite
  backup before invoking Ecto's forward migrator; signed updates must continue
  through the normal updater path.
- XERJ was unavailable, so the implementation was derived from the existing
  release, snapshot, migrations, and distribution code. No peer code was used.
- Ponytail 4.10.0 (MIT) kept the change to operation evidence and documentation;
  no new migration mechanism or dependency was added.

## Work performed

- Created a mode-`0600` SQLite online backup under the native application data
  directory before changing the database. Its SHA-256 is
  `bb2c8a92161c05b146fbbf9ab6db8586f119392aa2fe7d3e2dc40af46079acb2`.
- Applied migrations `20260919090000` and `20260920170000` from the already
  verified developer bundle. No pending-update marker or update-attempt row was
  fabricated.
- Removed the temporary mode-`0600` release credential immediately after the
  one-off migration command.
- Corrected the documented native application-data path and separated the
  local source-build maintenance procedure from the signed updater contract.
- Reopened the built application successfully; the shell and bundled Phoenix
  release remain running, with Phoenix listening only on `127.0.0.1:54722`.

## Verification

| Command or check | Result | Evidence |
| --- | --- | --- |
| `/usr/bin/sqlite3 ... 'PRAGMA integrity_check'` before migration | pass | Source and backup both returned `ok`. |
| Preflight projections | pass | 1 project, 0 active runs, 0 update attempts; no project knowledge/config files existed. |
| Bundled release `Ecto.Migrator.run(..., :up, all: true)` | pass | Exactly 2 expected migrations completed. |
| Integrity, migration, row-count, and foreign-key checks after migration | pass | Integrity `ok`; latest versions are `20260920170000` and `20260919090000`; 1 project retained; no foreign-key violations. |
| Native developer application launch | pass | Shell PID 4809 and bundled BEAM PID 4850 remained alive; listener is IPv4 loopback only. |
| `rtk env -u CR_PAT mix quality` | pass | 269 tests and 10 properties passed; Credo, Sobelow, and dependency audit reported no issues. Expected crash-fixture logs were emitted by the supervisor recovery test. |

## Residual risk

- This was a controlled local developer-data operation, not a signed update
  rehearsal. The private backup remains retained until the stakeholder finishes
  inspecting the migrated application.

## RTK exceptions

- `rtk proxy sqlite3` was used because the RTK sqlite wrapper changed URI-mode
  read-only handling; exact SQLite output was required for integrity evidence.
