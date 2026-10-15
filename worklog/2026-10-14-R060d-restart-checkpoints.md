# R060d — Recover settled battle checkpoints

Baseline: clean local main `b899371`, 15 commits ahead of origin/main. User asked
to update docs/AGENTS, analyze PLAN and continue implementation. The first pending
recovery gap is that `Battles.recover/0` sends even fully settled running boundaries
to needs-attention. No native cleanup or lost receipt may be inferred from this.

Ponytail full 5.2.0 (MIT), workflow-and-kanban, elixir-phoenix-liveview, local-runner,
security-review and quality-gates apply. RTK prefixes every repository command;
`rtk proxy` preserves exact source/protocol/build output. Reuse Battles transactions,
the existing runner startup and guarded Pause/Resume UI. No new dependency, native
grant, worker or migration. Claimed acceptance is in the task file.

Relevant source: `lib/cuckoding/battles.ex:610` startup recovery,
`lib/cuckoding/battle_runner.ex:10` recovery before polling,
`lib/cuckoding/battles.ex:340` settled receipt check and existing Resume guards.
No external mechanism or copied peer source is needed. Original evidence and
workspace bindings stay intact; live Cursor/mixed-provider acceptance remains open.

## Implementation and documentation audit

Reuse the settled-attempt predicate already used by Pause/Resume. Startup now
changes only settled running/pausing checkpoints to Paused, increments the control
revision, and atomically records `battle.recovery_paused` with stage/task/revision.
All attempt receipts, retry/skip history, task projections, reviewed heads, frozen
authority, turn budgets and original deadline remain unchanged. Existing clean
pauses are idempotent. Resume clears the displayed restart reason and retains the
existing exact-binding, budget and native-integrity gates. Missing/uncertain cleanup,
unfinished attempts and interrupted Stop remain needs-attention; no stage replays.

Arena explains the recovered pause using a status region and the existing Resume
control. No additional setup screen or permission flow. Unsaved text survives live
updates; stale revisions, recovered form keys and expired sessions remain refused.

PLAN now leads with a current implementation/remaining-work table. Split stale
blanket items for model catalogs, structured task transport, scoped team adoption,
task creation and check declarations into delivered implementation versus remaining
extensions/acceptance. Updated Product, Architecture, Data, Flow, Security,
Execution, Arena loop, UI, Development, Testing, README and AGENTS together.

## Verification

- `rtk proxy asdf exec mix format lib/cuckoding/battles.ex lib/cuckoding_web/live/battle_component.ex test/cuckoding/battles_test.exs test/cuckoding/battle_executor_test.exs test/cuckoding_web/battle_live_test.exs` — passed.
- `rtk proxy asdf exec mix test test/cuckoding/battles_test.exs test/cuckoding/battle_executor_test.exs test/cuckoding_web/battle_live_test.exs` — 81 passed. Covers every saved stage, retry/skip/Partial context, unchanged authority and deadlines, repeated startup, runner dispatch only after Resume and stale/session UI guards. Existing missing-cleanup and unfinished-worker cases remain covered.
- `rtk proxy asdf exec mix quality` — 298 passed; format/compile, Credo and security/dependency checks passed. Credo found no issues; Sobelow reported no vulnerabilities. The existing quoted-keyword warnings from lockfile scanning remain informational.
- `rtk proxy env PATH=/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/Users/mpak/.asdf/installs/erlang/28.5/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin bin/dev.build` — passed. Hex reported a cache read warning then resolved unchanged locked dependencies; the Hex update notice and OpenSSL relocation/signature warnings did not prevent the bundle. No dependency update was made.
- `rtk proxy bin/smoke` — passed bundled launch, bootstrap/cookie, authenticated routes, handoff replay/origin refusal, heartbeat, graceful quit and listener cleanup. Private smoke data: `/private/tmp/ccoding-smoke.CGPSwo`.
- `rtk proxy python3` local Markdown-target check — all 173 relative file targets in changed docs/task/worklog resolved. Source/claim checks matched the implemented scope. `rtk proxy git diff --check` passed.

No native source or schema change; Rust format/clippy/test suites were not rerun.
No live inference, real battle, physical crash/sleep test, manual browser visual QA
or clean-machine release verification was performed. Fixtures and bundled smoke
do not satisfy those gates. No site assets changed.

## Saved workspace and handoff

Process inventory found no running Cuckoding/CCoding or BEAM instance before the
build; earlier PIDs were gone and no process was signalled. The exact saved test
launcher was preserved. Its data root remains
`/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data`.

Created a mode-0600 online SQLite backup at
`.ccoding/r060d-validation/before-rebuild.sqlite3`. Before launch: schema 11,
57 settled commands (56 completed, 1 rejected), no battles, 2 Arenas/boards/drafts
and 2 named connection records. Reopened the rebuilt bundle using that launcher:
native PID 53846 and owned BEAM 53847 started 2026-10-14 22:12:56; BEAM cwd matches
the saved data root and listens only on `127.0.0.1:56981`. Browser bootstrap added
the expected `shell.authorized` and `browser.authorized` events. All 14 non-session/
event tables and the original 226 event rows match the backup exactly. Integrity
is `ok`, foreign-key violations zero, schema remains 11. No profiles or assignments
were substituted. Build and launch evidence is local, not publication.

Next: reconcile interrupted owned workers and native/Git effects, sleep-gap
accounting and safe backoff before parallel work (R060/R070). General subprocess
checks, broader provider/planning support, custom workflow, global worker/log UI,
real mixed-provider acceptance and signed clean-machine release remain open.
Commit this verified slice and fast-forward local main; no push or deployment.
