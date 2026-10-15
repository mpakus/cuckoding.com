# R060g worklog · 2026-10-15

Claim: `tasks/R060g-retained-integration.md`; branch
`fix/R060g-retained-integration`. Began on clean main at `99471f4`, 25 commits
ahead of origin/main. One recovery slice, no provider usage or remote publication.

Acceptance: verify existing native integration evidence without replay, retain
interrupted history, pause a reconciled in-budget boundary for explicit Resume,
and fail closed on absent/changed/expired evidence. New Starts freeze the policy.

Using Ponytail full, architecture, Elixir/LiveView, local-runner, security-review
and quality-gates. `rtk proxy` is used for exact source/script/build/test evidence
where filtering would hide protocol or assertion detail. Existing native fixed
Git verifier/locking and battle claim/state transitions are reused.

Implementation:

- D029 precedes the boundary change. New snapshots freeze the recovery policy;
  old snapshots receive none. Startup marks only interrupted integration after
  otherwise settled history. One monitored supervised task performs the read.
- Native `recover_integration` reuses pinned source identity, repository locking,
  retained ownership/candidate verification and exact request hashes. It requires
  intent, publication and receipt to agree with the original request and current
  app ref. It has no write/ref-update path and never fills in a missing receipt.
- SQLite stores a separate bound observation and checkpoint transactionally;
  the interrupted attempt remains immutable. In-budget results advance once to
  Paused, with a new control revision and explicit Resume. Original limits and
  bindings remain. Late verified effects close cleanup for Stop without accepting
  work. Failed reads remain blocked and are not polled repeatedly. A crash during
  inspection may repeat only the read; a crash after settlement retains the pause.
- The existing LiveView Inspect component shows pending/retained observations,
  including verified versus uncertain cleanup. Reconnect preserves the evidence.
  No schema, dependencies, provider grants or frontend framework were added.

Verification:

- Baseline executor/domain tests: 73 passed before new cases. Initial expanded
  checks exposed two test-fixture errors (immutable snapshot update and a wrong
  helper name); corrected fixtures without relaxing application immutability.
- `rtk proxy asdf exec mix test test/cuckoding/battles_test.exs test/cuckoding/battle_executor_test.exs test/cuckoding_web/battle_live_test.exs`:
  **104 passed**. Covers running/pausing reconciliation, original attempt retention,
  no duplicate completion, explicit Resume, historical/Stop/provider refusal,
  foreign/malformed receipts, expiry without advancement, atomic rollback,
  coordinator crash during read and after durable settlement, and UI reconnect.
- `rtk proxy asdf exec mix quality`: **339 passed**, formatter/compile clean,
  Credo no issues, Sobelow no vulnerabilities and dependency audit passed. The
  existing Sobelow quoted-keyword lockfile warnings remain. The first quality run
  requested simpler function boundaries; refactored and the final run passed.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`: passed.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`:
  passed.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked recovery_only_observes_complete_exact_integration_evidence`:
  passed, 12 complete/partial/drift/cancellation/deadline/lock scenarios, with
  unchanged source HEAD/index/working/untracked files and no missing-receipt repair.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`:
  **74 passed, 5 ignored**, 210.68 seconds. Ignored gates require explicitly
  selected Codex isolation/check runtimes, private Cursor preflight or consented
  real Codex/Cursor usage. They were not run or claimed passing.
- `rtk proxy bin/dev.server --port 0 --no-open --smoke`: passed session/reload/
  origin/CSP checks, no Tidewave. Temporary listener 65512 exited.
- `rtk proxy env PATH=/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/opt/homebrew/opt/erlang/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin bin/dev.build`:
  passed production Phoenix release and Tauri bundle. Expected OpenSSL relocation
  signature warnings were followed by re-signing. Six changed BEAM modules match
  the assembled production release bytes in the packaged bundle.
- `rtk proxy bin/smoke`: passed startup/bootstrap/cookie/origin/replay/heartbeat/
  graceful Quit/listener cleanup; retained root `/private/tmp/ccoding-smoke.f4e1Pu`.
- Markdown local-file references and `rtk git diff --check`: passed.

Saved workspace rebuild:

- Verified idle native PID 29323 / backend 29324, executable/parent/start identity,
  backend data cwd and loopback listener 51946. No active commands or battles;
  schema 11, integrity ok and zero foreign-key errors.
- Private online backup: `.ccoding/r060g-validation/before-rebuild.sqlite3` (0600).
  Used the documented idle-only audit-token-bound normal backend SIGTERM fallback
  after prior unavailable tray control. Both processes exited and listener closed;
  no forced native kill or provider-app signaling. This emits no tray Quit event.
- Reopened the exact saved `Open Cuckoding Test.command` without changing its data
  root. Current bundle native/backend PIDs 87968/87973, start 2026-10-15 17:49:17
  local time; actual listener `127.0.0.1:49331`. Private relaunch log is 0600.
- All saved tables unchanged except browser sessions and appended lifecycle events;
  existing 238 events retained, now 240 with only shell/browser authorization added.
  Agents, models, team revisions/adoptions, Arenas, boards, tasks, commands and battle
  history match the backup. Schema/integrity/foreign-key checks remain valid.
- Browser verified the authenticated dashboard and canonical Agents/Team/Arenas
  navigation on the new listener. Stopped UI inspection when the user changed
  Chrome; no account, role, task or execution action was submitted.

Limits and handoff:

This recovers only complete retained integrations for new grants. Missing native
receipts, other interrupted stages/provider stores, process/sleep/lease accounting,
safe backoff, parallel workers and live/clean-machine acceptance remain open. No
provider inference, sign-in, physical sleep drill or deployment occurred. Existing
saved legacy Codex/team assignments were preserved, including their current
connection readiness. Continue R060 before enabling R070 parallel scheduling.

Local integration: committed as `22d5d1f`, fast-forward merged into local `main`;
`fix/R060g-retained-integration` deleted. Final documentation records this evidence.
No remote push or publication performed.
