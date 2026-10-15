# R060f — Durable worker completion before coordinator notification

Claim: `tasks/R060f-durable-worker-handoff.md`. Baseline clean main `2d0145f`,
23 commits ahead of origin/main. Continue the plan's recovery work before parallel
scheduling, preserving R012's supervised async workers and LiveView conventions.

Applied Ponytail full 5.2.0 (MIT), project workflow, local-runner, Elixir/LiveView,
architecture, security and quality guidance. Existing skills suffice; no dependency
or install. RTK prefixes commands; proxy preserves source/protocol/test output.

Trace: Dispatcher/BattleRunner currently run effects in Task.Supervisor children,
then wait for the result mailbox message before Foundation.finish/Battles.finish.
A coordinator crash after the child finishes loses the receipt even though the
work ended. R012's grouped supervision correctly stops workers, but startup must
then mark this missing receipt uncertain. D028 records the change before code.

Use the same validated transactional settlement from the worker and return only a
completion signal. Coordinators retain admission/monitoring and progress ownership.
No result replay, new grant, state/table or acceptance shortcut. Missing receipts
still need inspection. Invalid/foreign battle results cannot establish cleanup.

## Implementation

- Dispatcher and BattleRunner workers settle through Foundation/Battles before
  returning `:settled`. Coordinators only flush the matched monitor, clear transient
  presentation state and reopen polling. A completion notification cannot cause a
  second write or own the only result. Existing transactional validation, events,
  projections and expiry remain authoritative.
- Unexpected execution/settlement exceptions exit the task with a fixed shutdown
  reason. Existing monitor handling records interruption without exposing exception
  payloads or inventing cleanup. Already committed terminal facts reject another
  settlement and remain immutable.
- BattleRunner no longer trusts a cleanup flag from invalid/foreign results.
  A Stop racing a valid finished stage reuses the full bound-result validator for
  cleanup only; the stage is cancelled and work cannot advance. Malformed Stop
  receipts remain needs-attention with unknown cleanup. No schema/grant/budget
  or independent-review rule changed. Native missing-receipt recovery remains open.

## Verification

- The first focused run reproduced all four mailbox-loss cases plus the invalid
  cleanup flag: 25/30 passed before implementation. After the fix, the cancellation
  fixture was adjusted to accept the existing absent/empty cleared catalog shape;
  no projection behavior was changed to satisfy the test.
- `rtk proxy asdf exec mix test test/cuckoding/dispatcher_test.exs test/cuckoding/battle_executor_test.exs test/cuckoding/battles_test.exs test/cuckoding_web/battle_live_test.exs`
  — 106 passed. Fixtures suspend coordinators while workers commit, then crash/
  restart: setup success/cancellation survive, a battle success reopens Paused
  at the next stage with explicit Resume, and failures remain immutable. Valid
  versus malformed Stop races, SQL rollback, private exception canaries and the
  existing expiry/session/reconnect boundaries pass without provider inference.
- `rtk proxy asdf exec mix quality` — 330 passed, formatter/compiler clear, Credo
  no issues, Sobelow no vulnerabilities and dependency audit passed. Existing
  Sobelow quoted-keyword lockfile-parser warnings remain tool diagnostics.
- `rtk proxy bin/dev.server --port 0 --no-open --smoke` — passed session, reload,
  origins, strict application CSP and no-Tidewave checks on temporary port 51770,
  then exited. Native/UI grants and site assets were unchanged.
- `rtk git diff --check` passed; 212 local Markdown file references validated.

## Packaging and saved data

- Verified the saved workspace idle: no battles or active setup commands;
  integrity/FK checks passed. Retained exclusive 0600 online backup:
  `.ccoding/r060f-validation/before-rebuild.sqlite3`. Used the documented normal
  backend stop bound to the exact macOS audit token, executable, parent/start
  identity and saved cwd. Old native/BEAM 21663/21664 and listener 49777 exited.
- `rtk proxy env PATH=/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/opt/homebrew/opt/erlang/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin bin/dev.build`
  — passed locked dependencies, production compilation and Tauri bundle. Expected
  OpenSSL relocation warnings were followed by replacement signatures.
- `rtk proxy bin/smoke` — passed bundled launch/bootstrap, browser cookie,
  handoff replay/origin refusal, heartbeat, graceful Quit and listener cleanup.
  Disposable smoke data remains `/private/tmp/ccoding-smoke.lCMshE`.
- The three changed BEAM modules match the assembled production release exactly
  in the bundle. Reopened the unchanged saved test launcher with data root
  `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data`. Native/BEAM 29323/29324,
  reported start identity 14:23:04, listener `127.0.0.1:51946`, cwd verified.
- Every saved table compared to the backup: agents/models/roles/boards/tasks,
  revisions and old events unchanged. Only browser-session rows and expected
  `shell.authorized`/`browser.authorized` events (236 → 238, matching sequence)
  changed. Integrity/FK checks passed; schema remains eleven migrations.
- Chrome's authenticated roster and Ura Mawashi board loaded: saved Cursor/c2
  selections, two Specs cards, Create tasks and board + controls present. Existing
  signed-out legacy Codex assignments still block Start; no substitutions, auth
  actions or provider usage were performed.

This closes committed completion's mailbox-loss window. It does not establish
native-effect reconciliation without receipts, physical crash/sleep recovery,
parallel scheduling, real-account battle acceptance or clean-machine release.
Rust/site source was unchanged, so their suites were not rerun. Implementation
`0819a3f` was fast-forward merged into local main; feature branch deleted. Final
integration status is recorded in this follow-up. No push/deployment.
