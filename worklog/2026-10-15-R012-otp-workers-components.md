# R012 — Asynchronous OTP workers and shared LiveComponents

Claim: `tasks/R012-otp-workers-components.md`. Baseline clean local main `112d2a3`,
21 commits ahead of origin/main. User requested an OTP/BEAM execution and LiveView
component audit with concrete refactoring.

Read the product, architecture, flow, data, security and execution contracts.
Applied project Elixir/LiveView, architecture, local-runner, security, quality and
Ponytail full 5.2.0 (MIT) skills. Existing skills cover this work; no installation
or new dependency is needed. RTK prefixes shell commands; proxy preserves exact
source, build and test output.

Audit: BattleRunner already dispatches through monitored Task.Supervisor workers.
Dispatcher executes external setup/planning inside its GenServer callback. Its
transient protected ETS login table is currently written in that same process.
Separate sibling task supervisors would outlive a crashed coordinator. Every
application screen is a LiveView; four stateful components use Phoenix directly
and repeat route setup. Auth/redirect/download/controller boundaries remain HTTP.

Acceptance is the task checklist. D027 records the worker/coordinator lifetime
boundary before implementation. Preserve single-command/stage capacity, durable
claims, explicit cancellation, unknown-cleanup handling, independent review and
all session/consent gates. No raw provider output or URLs enter persistent data.

## Implementation audit and result

- Traced every provider caller: Planning runs from Dispatcher; task turns run
  from BattleExecutor/BattleRunner. Only Codex and NativeHelper own Port receive
  loops. No System.cmd, raw spawn or unsupervised Task.start remains in `lib/`.
  Native helpers remain OS children; monitored BEAM tasks own their transport.
- ExecutionSupervisor creates independent setup/battle `one_for_all` groups.
  Dispatcher uses `Task.Supervisor.async_nolink`, correlated result/`:DOWN`
  handling and current-task-only login progress. Foundation commits interrupted
  worker/startup claims through the existing kind-specific event transaction;
  unknown native cleanup remains unknown. Discovery retains bounded lease retry.
- Protected ETS remains owned by Dispatcher. Validated URLs travel only through
  transient process messages/ETS and the existing protected redirect. Inspected
  the pinned Elixir 1.20 GenServer.format_status/1 callback documentation, then
  redacted status/error fields and proved a real handler/SQL failure cannot log
  the URL. No new API grants, schema, dependencies or skills were installed.
- Seven LiveView modules cover all ten application live routes. All four stateful
  components now use `CuckodingWeb, :live_component`; existing explicit event
  guards remain. Function-component layouts/dialogs and small browser hooks stay
  in place. Controller protocol/auth/download boundaries remain appropriate.
- Delayed shell Quit now sends a timer message to supervised ShellAuth instead
  of starting an unowned task; its existing durable quit event remains unchanged.

## Verification

- `rtk proxy asdf exec mix test test/cuckoding/dispatcher_test.exs test/cuckoding/battle_executor_test.exs test/cuckoding/authorization_test.exs test/cuckoding_web/planning_live_test.exs test/cuckoding_web/battle_live_test.exs`
  — 61 passed before the additional supervisor-fault/privacy fixtures.
- `rtk proxy asdf exec mix test test/cuckoding/dispatcher_test.exs test/cuckoding/foundation_test.exs test/cuckoding/battle_executor_test.exs`
  — 32 passed after those fixtures. Tests verify responsive coordinator state,
  task-owned Port, serialized admission, task/coordinator/task-supervisor death,
  unrelated-group survival, retained uncertain battle work, cancellation and
  transient/correlated login links, including actual crash-log redaction.
- `rtk proxy asdf exec mix quality` — final 322 passed, format/compiler clear,
  Credo no issues, Sobelow no vulnerabilities and dependency audit passed. Existing
  Sobelow quoted-keyword warnings parsing Mix's lockfile remain tool diagnostics.
  Initial checks exposed a stale standalone-dispatcher test setup, an incorrect
  test event-prefix expectation and a Credo nesting issue; fixed callers/fixtures
  and extracted the task-start helper. Task-supervisor fault injection suspends
  its idle coordinator to avoid killing an Ecto shared-sandbox transaction; this
  does not claim an actual native-process or power-failure drill.
- `rtk proxy bin/dev.server --port 0 --no-open --smoke` — passed session, reload,
  origins/CSP and no-Tidewave checks on temporary port 49554, then exited.
- `rtk git diff --check` passed; 210 local Markdown file references across 23
  documents validated. Structural audit confirms the shared macro and explicit
  session event guard in every stateful component.

## Packaged build and preserved workspace

- The prior saved workspace was idle (no battles or active commands); DB integrity
  and foreign keys passed. Retained exclusive 0600 online backup:
  `.ccoding/r012-validation/before-rebuild.sqlite3`. Used the documented normal
  backend shutdown bound to the exact macOS audit token, executable, parent,
  start and saved cwd. Old native/BEAM 16481/16483 and listener 64974 exited.
- `rtk proxy env PATH=/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/opt/homebrew/opt/erlang/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin bin/dev.build`
  — locked dependencies, production compilation and Tauri bundle passed. Expected
  OpenSSL relocation warnings were followed by replacement signatures.
- `rtk proxy bin/smoke` — passed bundled launch/bootstrap, browser cookie,
  handoff replay/origin refusal, heartbeat, graceful Quit and listener cleanup.
  Disposable data remains at `/private/tmp/ccoding-smoke.wKoSVi`.
- All eleven changed BEAM modules exactly match the assembled production release
  in the bundle. A first comparison against unstripped compiler output correctly
  differed; release assembly strips debug chunks, so assembled release bytes are
  the correct reproducibility comparison.
- Reopened the unchanged saved test launcher with data root
  `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data`. Native 21663 / BEAM 21664
  started at 13:45:53 and listen only on `127.0.0.1:49777`.
- Compared every saved table to the backup: connections, model choices, roles,
  boards, tasks/revisions and old events unchanged. Only browser-session rows and
  the expected `shell.authorized`/`browser.authorized` events (234 → 236, matching
  sequence) changed. Integrity/FK checks passed; schema remains eleven migrations.
- Browser visual inspection was unavailable because the Mac was locked; no unlock
  workaround was attempted. Existing LiveView component session/reconnect tests
  and packaged HTTP checks passed. No user profile import or provider call ran.

This proves supervised asynchronous dispatch and local artifact preservation.
It does not prove product parallel scheduling, native cleanup after a hard crash,
sleep reconciliation, real-account battle acceptance or a clean-machine release.
Rust/site sources and native grants are unchanged, so their suites were not rerun.
Implementation `9052733` was fast-forward merged into local main and the task
branch deleted. Final status is recorded in this documentation follow-up.
Working tree/packaged behavior is verified above; nothing was pushed or deployed.
