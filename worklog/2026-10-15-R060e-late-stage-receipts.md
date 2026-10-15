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

## Handoff

Implementation `b6af1a3` was fast-forward merged into local main; feature branch
deleted, no push. Rebuild/relaunch is pending the user's Quit response after tray
automation timed out. The last verified saved app remains the prior build on
`127.0.0.1:49852` (native 80158 / BEAM 80159); recheck ownership before any restart.
After graceful Quit, run `rtk proxy bin/dev.build` with the pinned toolchain PATH,
then `rtk proxy bin/smoke` and the preserved
`/private/tmp/cuckoding-r050c-proof-vvr7u4wp/Open Cuckoding Test.command` launcher.
Compare saved records/history to the private backup and verify the new listener.
Do not count prior packaged evidence as this source revision's build verification.
