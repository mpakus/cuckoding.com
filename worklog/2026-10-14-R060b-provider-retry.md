# R060b — Bounded provider retry

Baseline: clean local main `e19253d`, 13 commits ahead of origin/main. User asked
to continue pending work. No live provider inference or real Arena battle is
part of this slice; pending Cursor acceptance is separate.

Ponytail full 5.2.0 (MIT), workflow-and-kanban, local-runner, security-review, agent-adapter,
elixir-phoenix-liveview and quality-gates apply. RTK prefixes repository commands;
`rtk proxy` preserves exact source/protocol/build output. No dependency or new
scheduler. Native cleanup contracts stay unchanged.

Acceptance is in the claimed task. Existing source owners: Snapshot freezes
authority, Battles commits stage/control transitions and events, BattleExecutor
normalizes provider receipts, BattleComponent guards user controls. The native
provider helper returns normalized failures only after owned-group cleanup;
helper loss/nonzero exit reports uncertainty. Retain its normalized failed
tool/edit receipts instead of dropping them at the executor boundary.

Retry will use fresh attempt/session IDs and the same original limits, with a
frozen two-retry cap per task and shared final-stage scope. No review bypass,
native-effect replay, account/model fallback or live-session continuation.

## Implementation

- New Start snapshots freeze `recovery: provider-retry-v1` and two retries per
  task, with two shared final-stage retries. Earlier snapshots retain their gates.
- Battles uses the existing control revision and immediate transaction. Retain
  failed attempt IDs in context and `battle.retry_requested`; validate the exact
  latest failed role, normalized transient status, cleanup, all preceding settled
  attempts, original limits and current bindings. Concurrent/stale Retry loses.
- Writer retries return through new preparation/coordinator/Speculator using the
  same reviewed head; read-only roles repeat only the failed stage. No prior native
  intent is replayed. Failure counts survive review returns and restart.
- Executor retains normalized failed tools/changes instead of dropping them.
  TaskTurn preserves boolean cleanup evidence; explicit false becomes uncertainty.
  Inspect displays retained edit paths/hashes. Raw provider fields and thoughts
  never enter these receipts. No provider/runtime grant, schema or dependency change.
- Pause/Resume recognizes only failed attempts explicitly consumed by Retry as
  settled; an in-flight crash remains interrupted. Stop's cleanup gate stays intact.

## Verification

- `rtk proxy asdf exec mix test test/cuckoding/battles_test.exs test/cuckoding/battle_executor_test.exs test/cuckoding/task_turn_test.exs test/cuckoding_web/battle_live_test.exs`:
  **63 passed** before the final runner-restart regression. Initial cleanup test
  expected a success tuple; corrected it to the existing `cleanup_required` refusal.
- Final `rtk proxy asdf exec mix quality`: **276 passed**, compile/format/Credo
  clean, Sobelow no vulnerabilities and dependency audit passed. Initial Credo
  complexity findings were resolved with a named scope predicate and explicit
  receipt pattern. Removed one unused test binding before the final clean run.
  Existing Sobelow dependency keyword-quoting diagnostics remain.
- Tests cover two-task execution after a partial writer failure, unchanged source
  bytes, independent review, fresh worktree IDs, shared final caps, unchanged task
  criteria/review rounds, stale receipts, four concurrent retry clicks, expiry,
  changed authorization, uncertain cleanup, policy/native failures, historical
  snapshots, restart/no implicit dispatch, Pause/Resume and expired/recovered forms.
- Native source is unchanged, so Rust unit/lint suites were not repeated. Physical
  sleep, uncertain-effect reconciliation and live-provider acceptance are not
  established by these fixtures. No provider inference was run.
- Native UI inspection again timed out (`-10005`); no visual QA pass is claimed.
  Verified idle DB, native/BEAM executable/start identity, cwd and listener before
  restart. Saved a private integrity-checked SQLite backup at
  `.ccoding/r060b-validation/before-rebuild.sqlite3`. Sent graceful SIGTERM only to
  owned BEAM 51373; native 51372 exited via heartbeat. Both processes and listener
  60676 were absent before building. No lock removal or force kill.
- `rtk proxy env PATH=/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/Users/mpak/.asdf/installs/erlang/28.5/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin bin/dev.build`:
  passed, one `Cuckoding.app` bundle; expected OpenSSL relocation/signature warnings.
- `rtk proxy bin/smoke`: passed packaged launch, bootstrap, browser cookie,
  handoff replay/origin refusal, heartbeat, graceful quit and listener cleanup.
  Evidence: `/private/tmp/ccoding-smoke.FnY1OD`.
- Relaunched unchanged saved test launcher. Verified native 90399 / BEAM 90400,
  started 2026-10-14 12:35:51 local, exact bundle/cwd and loopback-only listener
  `127.0.0.1:51967`. Compared all 14 non-session/event tables byte-for-byte with
  the backup; prior events also match, with only expected shell/browser authorization
  events appended. Schema remains version 11; integrity/FKs pass. No battles or
  active commands; agents, models, team and task records remain unchanged.
- Local Markdown links: 165 passed. `rtk proxy git diff --check`: passed.

## Delivery and handoff

R060b is complete for explicitly retried settled provider failures. Integrate into
local main and delete its merged branch; no push/deploy. Updated docs, AGENTS and
README distinguish this boundary from broader recovery. The saved test app runs
at `http://127.0.0.1:51967/`. Live Cursor acceptance remains pending, with no profile
or role substitutions. Next independent recovery slice is Skip with deferred
dependents and unfinished-work preservation; full crash/sleep reconciliation,
parallel workers, general toolchain checks, other providers and release acceptance
remain open in `docs/PLAN.md`.
