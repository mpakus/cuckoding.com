# R060a — Pause and resume

Baseline: clean local main `8c8c4f3`, ahead of origin/main by 12 commits.
User requested continued development. Cursor assignments remain unchanged;
synthetic Cursor usage approval and legacy Codex sign-in are still pending.
No provider inference or real Arena execution is authorized by this task.

Ponytail full 5.2.0 (MIT), workflow-and-kanban, local-runner, security-review,
elixir-phoenix-liveview and quality-gates apply. RTK prefixes shell commands;
`rtk proxy` preserves exact source, migration and build output.

Acceptance is in the task file. Scope: finish the already-claimed bounded stage,
retain its receipt, then pause before the next stage. No new runtime grant, native
session continuation, automatic retry or dependency. Stop retains cancellation.
SQLite owns pause/resume intent and guards stale control revisions. Keep the
original deadline; pausing cannot reset budgets. Full interrupted-work recovery,
sleep accounting, Retry/Skip and parallel workers remain separate tasks.

Initial live inspection: no battles or pending/running commands in the saved test
workspace. Native 31745 / BEAM 31748 still run the previous bundle; the assigned
legacy Codex observation is `not_connected`. No profile substitutions or edits.

## Implementation

- Added `control_revision` and extended the active-Arena partial index in the
  eleventh forward-only migration. No immutable snapshot or attempt rewrite.
- Pause/Resume live in the existing transactional battle context; no new runner,
  adapter, dependency or provider grant. An in-flight claim remains active during
  Pausing; verified settlement commits Paused before the runner can claim again.
- Failure/review exhaustion/uncertain cleanup takes precedence over pausing.
  Final completion is terminal. Stop still cancels active work and retains effects.
  Historical completed receipts without cleanup proof cannot be used to unlock
  an uncertain Arena. Clean paused boundaries survive runner/app restart; paused
  deadlines continue running and interrupted Pausing never resumes automatically.
- Session/form keys and persisted revisions reject stale/recovered UI actions.
  Exact connection observations are rechecked before Resume, and native validations
  still precede subsequent effects. No saved team/model fallback.

## Verification

- Focused domain/runner/LiveView suite: 45 passed before the final two uncertainty/
  deadline regressions. Final `rtk proxy asdf exec mix quality`: **263 passed**,
  format/compile/Credo clean, Sobelow no vulnerabilities. Existing Sobelow dependency
  keyword-quoting warnings remain. Initial Credo nesting feedback was fixed by
  extracting the single pause transition; a LiveView session-expiry test now waits
  for the preceding rendered update before expiring authorization.
- SQLite backup/copy: `.ccoding/r060a-validation/prior-schema.sqlite3` (private,
  integrity checked). An isolated copy includes one synthetic needs-attention battle;
  no synthetic record entered the user's database.
- `rtk proxy env MIX_ENV=test asdf exec mix run --no-start -e 'Application.ensure_all_started(:ecto_sqlite3); defmodule MigrationCheckRepo do use Ecto.Repo, otp_app: :cuckoding, adapter: Ecto.Adapters.SQLite3 end; {:ok, _} = MigrationCheckRepo.start_link(database: Path.expand(".ccoding/r060a-validation/migration.sqlite3"), pool_size: 2); IO.inspect(Ecto.Migrator.run(MigrationCheckRepo, Path.expand("priv/repo/migrations"), :up, all: true, log: false), label: "Applied migrations")'`
  applied only `20261014000000`. The initial dev-environment attempt refused before
  starting because no shell data-root environment was provided; the isolated test
  environment avoids starting application services.
- Python SQLite validation compared SHA-256 of every previous table's rows/columns
  to the pre-migration manifest, checked integrity/FKs, zero initial control revision,
  and both paused/pausing unique-index refusals: passed. Live data stayed unchanged.
- Native source/grants are unchanged; Rust lint/unit suites were not repeated.
  Full process cleanup/path/port/simulated or physical sleep coverage is not claimed
  by this completed-stage control slice. Packaged smoke remains required below.
- Native UI inspection timed out, so tray Quit could not be driven. After verifying
  idle DB, executable/PID/start identity, cwd and listener, backed up the live DB
  again and sent SIGTERM to only its BEAM child 31748. The shell's heartbeat exited
  31745 afterward. Verified both processes and the 50339 listener gone before build.
  No lock was removed, no unrelated process signalled and no force kill used.
- `rtk proxy env PATH=/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/Users/mpak/.asdf/installs/erlang/28.5/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin bin/dev.build`:
  passed, one current `Cuckoding.app` bundle. Existing Hex update notice and OpenSSL
  relocation/signature warnings remain; packaging completed successfully.
- `rtk proxy bin/smoke`: passed bundled launch, bootstrap, browser cookie,
  handoff replay/origin refusal, heartbeat, graceful quit and listener cleanup.
  Isolated smoke evidence: `/private/tmp/ccoding-smoke.1CNxlO`.
- Relaunched the unchanged `Open Cuckoding Test.command` in the saved
  `/private/tmp/cuckoding-r050c-proof-vvr7u4wp` workspace. Verified native PID 51372,
  BEAM child 51373, both started 2026-10-14 09:04:56 local, expected bundle/cwd,
  and loopback-only listener `127.0.0.1:60676`.
- Live migrated DB passed integrity/FK checks and contains migration
  `20261014000000`. Compared every existing public-domain table's previous columns
  with the verified `.ccoding/r060a-validation/before-rebuild.sqlite3` backup:
  workspace, all 57 commands, connections, team revisions/adoptions, Arenas,
  Tabulae, drafts/revisions and check revisions are unchanged. Only two expected
  shell/browser authorization events were appended. No battles or active commands.
  A first read-only command query used `status`; inspecting the schema and querying
  the actual `state` column confirmed 56 completed and one rejected command.
- Local Markdown links: 163 checked, passed; `rtk proxy git diff --check`: passed.
  UI contract documentation now describes Pause/Resume as implemented. LiveView
  interaction tests and packaged smoke are the evidence; native visual inspection
  remained unavailable after its timeout, so no visual pass is claimed.

## Delivery and handoff

R060a is complete for clean completed-stage boundaries; integrate this verified
slice into local `main` and remove its merged feature branch. No push/deployment.
The current test app is running at `http://127.0.0.1:60676/` with the saved workspace.
No live provider inference or real Arena battle was run. Cursor synthetic
acceptance and the assigned legacy Codex sign-in still need their pending user
actions; no agent/model/profile was substituted. Full uncertain-effect recovery,
Retry/Skip, sleep reconciliation, parallel workers and broader release acceptance
remain in `docs/PLAN.md`.
