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

Integration, build, migration and current-runtime results follow below.
