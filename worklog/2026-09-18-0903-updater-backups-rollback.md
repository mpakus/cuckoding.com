# Worklog — 0903 updater, backups, migrations, and rollback

## Metadata

- Date/time (UTC): 2026-09-18
- Task: 0903
- Status: complete
- Human/agent owner: codex
- Branch: `feature/0903-updater-backups-rollback`
- Start revision: `2582cd8`
- End revision: recorded by the Task 0903 commit

## Acceptance criteria

- Accept update state transitions only from the authenticated shell and verify
  the updater signature before installation.
- Require all active runs to hibernate before a schema-changing update.
- Snapshot the SQLite database, knowledge files, and configuration before
  migration; retain the recorded active-run inventory and update audit trail.
- Run forward migrations with visible progress, launch the candidate, and
  promote it only after bounded health checks pass.
- Roll back the application and restore compatible data after failed health,
  while refusing to launch an older binary against an incompatible database.
- Provide a safe mode that opens authenticated history without starting
  runners; Task 0904 owns the diagnostics export.
- Pass a repeatable update and rollback drill.

## Reference coding

- Focused XERJ searches covered the project, Hydra, and Vibe Kanban indices.
- Vibe Kanban's Apache-2.0 config migration backs up the prior file before a
  potentially incompatible conversion at
  `crates/services/src/services/config/versions/v6.rs:46-75`. Cuckoding adapts
  only the backup-before-migration ordering and adds database, knowledge,
  version-compatibility, health, and audit boundaries.
- Tauri's official updater contract requires signed update bundles and embeds
  the public verification key in application configuration. The private key is
  release-only and must not enter the application or repository.

## Work performed

- Claimed Task 0903 and restated the safety and rollback gates.
- Added durable update attempts and append-only lifecycle events, authenticated
  shell transitions, version guards, and a private pending-update marker.
- Added hash-verified SQLite, knowledge, and configuration snapshots with
  symlink rejection, failed-database retention, and non-destructive restore.
- Integrated Tauri's signed updater with exact-version two-click confirmation,
  hibernation, current-app backup, candidate health promotion, and app/data
  rollback on migration, installation, relaunch, or READY failure.
- Added guarded release migrations, safe mode, signed updater artifact and
  `latest.json` generation, release-key isolation, CI inputs, and operating
  documentation.
- Applied Ponytail full mode: reused Ecto, SQLite `VACUUM INTO`, Tauri updater,
  existing shell authentication, and the current release verifier instead of
  adding another service, scheduler, backup format, or UI framework.

## Verification

- `rtk mix quality` — passed: formatter, warnings-as-errors compile, 10
  properties and 195 tests with zero failures, strict Credo with no issues,
  Sobelow with no findings, and Hex audit with no advisories.
- `rtk proxy env -u GEM_HOME -u GEM_PATH PATH=/usr/bin:/bin:/usr/sbin:/sbin
  /usr/bin/ruby desktop/release_metadata_test.rb` — 6 runs, 15 assertions, zero
  failures.
- `rtk proxy cargo test --manifest-path desktop/src-tauri/Cargo.toml` — 7
  tests passed, including exact-version confirmation and safe-mode marker
  confinement.
- `rtk proxy cargo clippy --manifest-path desktop/src-tauri/Cargo.toml -- -D
  warnings` and Cargo format check — passed.
- `rtk proxy sh desktop/build.sh` — production release, native dependency
  bundle, Rust gates, `.app`, and all 34 sterile checks passed. The added drill
  created a real snapshot, crossed the install gate, changed the SQLite schema,
  restored compatible data, retained the failed database, recorded rollback,
  and removed the pending marker without lock warnings.
- Tauri signer drill with a disposable private key produced the detached
  `.app.tar.gz.sig`; all temporary key material and artifacts were removed.
- `rtk sh -n desktop/release.sh` and `rtk git diff --check` — passed.
- A production updater endpoint and long-lived Tauri signing key are deployment
  inputs, intentionally not generated or stored in the repository.

## Handoff

Task complete. Task 0904 may add the diagnostics export linked from safe mode.
