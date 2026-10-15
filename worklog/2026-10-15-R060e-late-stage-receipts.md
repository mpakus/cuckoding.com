# R060e — Retain expired stage evidence

Baseline: clean local main `deb1536`, 18 commits ahead of origin/main. Continue
the R060 recovery work before parallel scheduling. Claim and acceptance:
`tasks/R060e-late-stage-receipts.md`.

Ponytail full 5.2.0 (MIT), workflow, Elixir/LiveView, local-runner, security and
quality guidance reviewed. RTK prefixes shell commands; `rtk proxy` preserves
exact source/build/test output. No dependencies, native grants or provider calls.

Trace: BattleRunner receives normalized BattleExecutor receipts, Battles.finish
binds the attempt and stores the terminal outcome, and BattleComponent renders
retained public evidence. Currently the deadline branch replaces that evidence
with a status-only interrupted marker, losing known cleanup and edits. Stop then
cannot close the battle even after successful worker cleanup.

Use the existing receipt validation, immutable terminal-attempt trigger and
transaction/event boundary. Add an expired terminal attempt outcome; it retains
the receipt but cannot advance, Resume, Retry or Skip. Confirmed Stop may release
Arena exclusion only with verified cleanup for every attempt. Historical uncertain
outcomes stay blocked. No artifact deletion, runtime signalling, account changes
or implicit acceptance. Full uncertain-native and sleep reconciliation remain open.

## Verification

- `rtk proxy asdf exec mix test test/cuckoding/battles_test.exs test/cuckoding/battle_executor_test.exs test/cuckoding_web/battle_live_test.exs`
  — initial focused run 87 passed; 88 passed after covering the real executor's
  deadline cancellation shape. All stage boundaries retain evidence without head/
  task advancement or Resume/Retry/Skip. Invalid/foreign/duplicate outcomes refuse;
  verified Stop and unknown-cleanup refusal retain the immutable receipt.
- `rtk proxy asdf exec mix quality` — 313 passed after the added immutable failed-edit
  and uncertain-cleanup LiveView checks. Formatter/compiler passed, Credo clear,
  Sobelow no vulnerabilities; existing quoted-keyword lockfile-parser warnings.
- A final HEEx whitespace/readability adjustment was followed by format and
  `rtk proxy asdf exec mix test test/cuckoding_web/battle_live_test.exs` — 22 passed.
- `rtk proxy env MIX_ENV=prod asdf exec mix compile --warnings-as-errors` — passed.
- `rtk proxy bin/dev.server --port 0 --no-open --smoke` — passed session,
  reload, origins and strict CSP checks, then exited with no preview process left.
- `rtk git diff --check` and Python validation of 205 local documentation references
  — passed. No schema/native/site/dependency changes, so native/site suites were
  not rerun. No live-provider or physical sleep/recovery acceptance is claimed.
- Saved-workspace integrity/FK checks passed, with no active battle/setup command.
  A new exclusive 0600 backup is `.ccoding/r060e-validation/before-rebuild.sqlite3`.
  Tray automation timed out again; requested manual Quit under AGENTS.md's graceful
  restart rule. No forced termination. Packaged replacement remains pending Quit.

The prior running app is a separate artifact; source changes do not update it
automatically. Missing native receipts, full recovery, sleep reconciliation,
parallel workers and real-provider beta acceptance remain open.

## Local integration

Implementation `b6af1a3` was fast-forward merged into local main; feature branch
deleted, no push. `d0ba482` recorded the then-pending packaged rebuild.

## Packaged completion — 2026-10-15

- The user reported the tray menu missing/unresponsive after automation timed out.
  Verified the old native/BEAM identities (80158/80159, start 00:13:38), executable,
  parent, saved cwd and listener 49852. The DB contained no battles and no active
  commands; integrity/FK checks passed. Exclusive 0600 online backups are retained
  under `.ccoding/r060e-validation/` as `before-normal-stop.sqlite3` and
  `after-quit.sqlite3`.
- Used the backend's macOS audit token to bind a normal `SIGTERM` shutdown to that
  process, following Erlang's documented `init:stop()` behavior and the existing
  shell fallback. Backend and native shell exited; listener closed without forced
  kill. Every table was unchanged through shutdown. No tray quit event is claimed.
  The first identity assertion refused before any effect because `ps` pads columns;
  separate exact executable/start reads resolved that formatting mismatch.
- `rtk proxy env PATH=/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/opt/homebrew/opt/erlang/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin bin/dev.build`
  — passed with locked dependencies, production compilation and Tauri app bundle.
  Expected OpenSSL relocation warnings were followed by replacement signatures.
  OTP 28.5 is the installed Homebrew toolchain; the old asdf Erlang path is absent.
- `rtk proxy bin/smoke` — passed bundled launch/bootstrap, browser cookie, replay/
  origin refusal, heartbeat, graceful Quit and listener cleanup. Disposable smoke
  data remains at `/private/tmp/ccoding-smoke.gYEWJK`.
- Reopened the unchanged saved launcher
  `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/Open Cuckoding Test.command`.
  Native 16481 and BEAM 16483 started at 13:27:39 with the saved data root
  `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data`; listener `127.0.0.1:64974`.
- Compared every saved table with the post-shutdown backup: agents, model choices,
  team/task revisions and old events unchanged. Only browser session rows and
  `shell.authorized`/`browser.authorized` events (232 → 234, matching sequence)
  changed. Integrity/FK checks passed; schema remains 11 migrations. Retained counts:
  2 additional connections, 2 Arenas, 2 boards, 2 team revisions, 2 drafts/revisions
  and 57 commands.
- Chrome's authenticated UI confirmed the roster/Add agent, Team/Add role, both
  Arenas and Ura Mawashi's two Specs cards. Its saved legacy Codex Speculator/
  Secutor bindings remain signed out, while Cursor and c2 remain signed in.
  No role substitution, authorization change or provider inference was performed.
- Task, plan, README and contributor/development restart instructions now reflect
  completion. `rtk git diff --check` passed; the Python reference check validated
  206 local Markdown file references across 23 documents. This verifies local
  packaging and preservation; real-account battle,
  sleep/recovery and clean-machine beta acceptance remain open. No push/deployment.
