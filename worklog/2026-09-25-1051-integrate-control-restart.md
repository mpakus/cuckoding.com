# 1051 — Local integration and developer-app restart

User authorization: merge everything into main and restart the app. Acceptance:
verify and commit the existing board-controller/docs changes, integrate into
local main, build the new app, preserve existing data through any required
forward migration, and verify one healthy owned application instance.

Claim task 1051 only. Starting branch `feature/1049-board-controller`, revision
`55f1bd1`; local main is `caed0e7`. Existing task 1049/1050 changes are the requested
work. Other worktrees remain untouched. Remote publication is not requested.

Applied Ponytail 4.10.0 (MIT), full mode, quality-gates, local-runner,
security-review and menubar-shell guidance. Reuse the current build/restart and
documented developer-data upgrade paths. No product-code changes are planned.
Record native/provider checks separately from deterministic tests and this
local unsigned build. All shell commands use RTK; build/restart internals use
their existing exact-output proxy commands.

## Pre-integration verification and backup

- `rtk env -u CR_PAT mix quality`: passed 369 tests and 10 properties, seed
  974065, 0 failures; formatter, unused-lock check, warnings-as-errors compile,
  strict Credo, Sobelow and Hex audit passed. Expected crash-fixture messages
  belong to the supervisor tests.
- `rtk node --test test/task_board_motion_test.cjs`: 1 test passed.
- `rtk git diff --check`: passed.
- Reused `DeveloperRestart.processes`, descendant identity checks, graceful TERM
  and bounded cleanup wait from `bin/dev.restart`, via `rtk env -u GEM_HOME
  -u GEM_PATH /usr/bin/ruby -e ...`. The only Cuckoding shell was PID 76770,
  bundled BEAM 76847, healthy on loopback 64521. Both and the owned child exited
  gracefully. No unrelated process was signalled. The existing DBngin PATH
  warning is unrelated; no permissions were changed.
- `rtk python3 /tmp/cuckoding-1051-data.py backup`: confirmed the database was
  closed, integrity `ok`, no foreign-key violations and no active runs. Created
  a private mode-0600 online backup at
  `~/Library/Application Support/com.cuckoding.desktop/manual-backups/1051-20260926T034615Z/cuckoding.sqlite3`.
  SHA-256: `442d73ddf727ca5d057ff289a40dcd951bac484247021cb64477f53f57410da2`.
  All 44 tables matched the independently verified backup; no project knowledge
  or project.yml files existed to copy. Retained 1 project, 1 board, 13 tasks,
  2 runs (blocked/done), 6 sessions and 6 usage records.
- The only pending migration is `20260925120000`, adding batch tables and a
  nullable run association. Backup and verification use Python's standard SQLite
  API; exact process/database-open checks use `rtk proxy` to preserve output.

## Integration, build and current runtime

- Committed all 52 changed files as `e83fb67` (`feat(control): add sequential
  board development controller`), including the implementation, task 1050 docs
  and this operation's initial evidence. `rtk git switch main` and
  `rtk git merge --ff-only feature/1049-board-controller` fast-forwarded local
  main from `caed0e7`, including proposal commit `55f1bd1`. No merge conflict or
  discarded work; no remote push.
- `rtk env -u CR_PAT ./bin/dev.build`: passed from clean main at `e83fb67`.
  Production asset build, warnings-as-errors compilation and release assembly
  passed. Metadata tests: 6 runs/15 assertions; restart tests: 6 runs/98 assertions;
  release promotion passed; Rust formatting, 10 tests and Clippy with denied
  warnings passed; Tauri produced the unsigned developer bundle.
- The build's sterile verifier passed startup/READY, one-time authentication,
  authenticated browser handoff/settings rendering, diagnostics redaction,
  graceful shutdown/descendant cleanup, pre/post-readiness crash handling,
  safe-mode and update snapshot/migration/rollback checks. These use disposable
  data, not the user's provider sessions or a separate clean Mac.
- `rtk python3 /tmp/cuckoding-1051-migrate.py`: applied exactly
  `20260925120000` using the newly built bundle's Ecto forward migrator. The
  temporary private bootstrap file was removed in `finally`; no signed-updater
  marker or update-attempt record was fabricated.
- `rtk python3 /tmp/cuckoding-1051-data.py verify`: integrity and foreign keys
  passed. Counts and complete original-column row hashes matched for all 43
  existing data tables; only the schema-migration record and empty batch tables
  were added. The verified backup remains retained.
- `rtk ./bin/dev.restart`: passed. One owned shell (PID 75985, start
  2026-09-25 22:48:29 local) and its bundled BEAM (PID 76059, 22:48:30) run from
  `desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`. The only release
  listener is `127.0.0.1:62527`; `/health` reports application, SQLite, PubSub and
  endpoint `ok`, version 0.1.0. Fresh process inventory used executable and
  PID/start identity only, never raw argv or environments.
- Post-launch read-only checks still find 1 project, 1 board, 13 tasks, 2 runs,
  6 sessions and 6 usage rows, with integrity `ok` and no FK violations. No board
  batch or provider work was started for acceptance.
- Bundled controller, decision and board LiveView BEAM files match the freshly
  built production release byte-for-byte. Shell SHA-256:
  `5d6c951270e7566f7c363b2c9488d431f6ce5102ac91011f73c832707828987e`;
  BoardControl BEAM SHA-256:
  `6673150b9b50352952c56e550aab652ec0b1a9aa95c2424c9a36073b77106dbe`.
  These tie the verified process paths to the clean `e83fb67` build; `/health`
  itself reports a version, not a source revision.

## Limits and final handoff

Computer Use could inventory the desktop but timed out selecting the tray-only
Cuckoding application. No authenticated visual inspection of the user's native
dashboard is claimed. The build's isolated authenticated-browser smoke passed;
task 1049 retains its separate desktop/mobile feature evidence. Open the current
dashboard with the Cuckoding menubar action.

This is local main integration and an unsigned developer-app restart, not remote
publication, signed clean-machine acceptance, physical sleep/wake testing or a
real-provider multi-task board run. Those feature/release gates remain open.
The closing commit changes task/worklog/documentation only; the running executable
is the `e83fb67` source build. Final whitespace and clean-tree checks are recorded
with the closing commit; no source rebuild is needed for this evidence-only edit.

Final checks: `rtk git diff --check` passed. Reusing
`rtk python3 /tmp/cuckoding-1050-doc-check.py` passed 46 Markdown files, 179 local
links/anchors and all 276 implementation hashes. `rtk git status --short --branch`
after the closing commit confirms clean local main; origin/main is unchanged.
