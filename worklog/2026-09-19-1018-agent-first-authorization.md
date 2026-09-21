# 1018 — Agent-first authorization

## Scope and acceptance

Authorize a saved machine-wide agent once, select it across projects and roles,
automatically check unique connections at start, and reconnect only when needed.
Keep execution configuration separate and preserve existing board tasks
and historical snapshots. Full acceptance is in task 1018.

Preserved completed task 1017 as local commit `9ca4879`; new work is on
`feature/1018-agent-first-authorization`. Unrelated `icon.png` remains untouched.
Git index/ref writes required sandbox escalation. No push/merge in the initial
documentation tranche; the September 20 continuation requests a local merge.

## Inspection and skills

- Ponytail 4.10.0 full (MIT), architecture, adapter, security-review, LiveView,
  workflow, quality-gates: reuse the catalog, document the auth/state boundary
  before implementation, do not replace credential reuse with broad home sharing.
- OpenAI Docs: fetched official authentication documentation. It establishes
  cached login and credential-store modes, not cross-home credential reuse.
- Read AgentRuntime, GuidedRun setup collection, run-page rendering, Codex and
  Cursor adapter setup, current product/configuration/architecture/security docs,
  and ADR-024. Existing run setup enumerates roles; Codex account login and run
  probes select different homes; Cursor isolates HOME/config/compatibility dirs.
- Memory quick lookup found no relevant authentication implementation guidance.
- RTK proxy used for exact source/instruction reads. No credentials, Keychain
  entries, auth files, or provider sessions were read or changed.

## September 19 specification tranche / historical handoff

Documented the accepted target flow and implementation order, including a
reviewed legacy-board upgrade instead of telling users to recreate boards.
Current runtime behavior is unchanged. Credential-only reuse remains the
default boundary. Asked whether broader shared app-owned profile/session state
is acceptable; no such authority is inferred from shared-credential reuse.

Before changing storage or running authenticated acceptance, resolve the
provider-specific credential-only mechanism (or receive the explicit shared
profile decision). Do not claim authorize-once works from saved metadata or
mocked probe tests. Task remains incomplete.

Initial documentation checks:

- `rtk git diff --check` — passed.
- `rtk proxy ruby -e ...` — checked task, worklog, and flow existence plus their
  relative Markdown targets; passed. Proxy preserves exact validation output.
- No product tests claimed for the initial specification-only tranche.

## 2026-09-20 implementation continuation

User explicitly selected shared app-owned agent profiles across projects and
requested merging completed work to main. This supersedes the earlier
credential-only default, not the prohibition on personal/global CLI homes.
Acceptance: stable per-account sign-in/probe/launch paths, separate per-run
permissions, global management, grouped roles, explicit legacy bindings,
regression/security/UI checks, then merge. No credentials are copied or printed.

XERJ localhost:9200 is unavailable; source fallback inspected the pinned
vibe-kanban Codex executor (Apache-2.0) for home selection versus launch
configuration. Installed Codex 0.146.0 help confirms --ignore-user-config;
installed Cursor source resolves auth from HOME and config from CURSOR_CONFIG_DIR.
RTK proxy is used for exact reads and unfiltered verification output.

Reference: vibe-kanban commit `735654971bd396aa97b65166955678e4c34f8bf8`,
`crates/executors/src/executors/codex.rs:14-26,35-46` (Apache-2.0): separate home
selection from launch configuration. No source copied; Cuckoding excludes
personal-home fallback and keeps execution permissions/instructions run-owned.

### Delivered

- Reused the existing provider account catalog for the independent Agents page,
  shared Codex/Cursor profiles, audited settings/status changes, automatic unique
  account checks and grouped role cards. No dependency or schema migration.
- Explicit board upgrades and queued-run binding events preserve tasks and past
  snapshots; compatibility checks reject runtime/executable/helper mismatches.
- Symlink checks, private profile directories, fixed Cursor MCP/sandbox config,
  Codex ignored user config/rules and per-run grants retain execution boundaries.
- Updated product, architecture, security, configuration, flow and test docs.
- Applied Ponytail full, architecture, agent-adapter, security-review, LiveView,
  workflow, quality-gates, OpenAI Docs, accessibility and UX-writing guidance.

### Verification

- `rtk env -u CR_PAT mix quality` — exit 0: formatter, warnings-as-errors compile,
  254 tests and 10 properties (zero failures), Credo (3,199 functions, no issues),
  Sobelow and Hex audit (no advisories). Expected crash-fixture logs are not
  failing tests. Earlier focused tests exposed nested audit transactions; fixed
  shared transaction ownership and reran successfully. Credo nesting fixed.
- `rtk env -u CR_PAT mix assets.build` — exit 0, Tailwind and esbuild succeeded.
- `rtk git diff --check` — passed again after final documentation edits.
- `rtk env -u CR_PAT mix format --check-formatted` — exit 0 after module-doc
  corrections; initial sandbox attempt could not open Mix's local PubSub socket,
  so verification used the approved escalation (not an application failure).
- `rtk proxy env -u CR_PAT PHX_SERVER=true mix phx.server` — local server running
  on loopback port 4000; health endpoint reports database/PubSub/endpoint OK.
  Proxy preserves streaming output. Corrected development startup instructions
  because runtime configuration requires PHX_SERVER explicitly.
- Browser: Agents page renders at desktop and 320px; document width equals
  viewport width at 320px. Native keyboard Enter opens Edit Speculator. Async
  checks show disabled checking state and then observed status/UTC check time.
  Both real installed CLIs report sign-in required for these saved profiles.
  No provider task was launched. A later keyboard/copy check was not completed
  because browser automation timed out; viewport override was reset.
- LiveView tests cover independent catalog creation/editing and live persisted
  status. Deterministic runtime tests cover reuse, two-account separation,
  role settings, simulated revocation, stale probes, unsafe paths/MCP and legacy
  history preservation. These are not real authenticated-provider evidence.

### Remaining acceptance / handoff

Sign in once to each app-owned profile in Agents, then verify authenticated runs
in two projects, restart/refresh and concurrent provider behavior. Task 1018 stays
in progress until that evidence exists. No clean-machine native packaging or
release certification claimed. Detailed project impact lists and revoke/delete
controls are follow-ups. Personal CLI homes and unrelated `icon.png` are untouched.
Local merge to main is requested; no remote push is part of this continuation.

## 2026-09-20 lifecycle continuation

Continued on `feature/1018-real-provider-acceptance` after task 1020 merged to
local `main`. Acceptance for this tranche: show the full current project/role
impact of one shared provider identity, require explicit confirmation before
disconnecting it, preserve running/history state, and record a value-free event.
The provider session otherwise has no Cuckoding TTL and persists until provider
expiry/revocation or an explicit disconnect.

XERJ remained unreachable at `http://localhost:9200`; direct source inspection
reused the existing provider-account, app-owned profile, adapter probe, EventStore,
and LiveView patterns. Installed `codex logout --help` and `cursor-agent logout
--help` confirmed native scoped logout commands. No dependency or migration was
added.

### Delivered

- Root cards aggregate linked saved agents and current project, board, and role
  assignments. Linked cards still point to the root and never duplicate login or
  logout controls.
- A confirmed asynchronous **Disconnect shared sign-in** action runs only the
  provider CLI with the app-owned profile environment. It records the request
  before the external action and `provider.authorization_disconnected` after success, changes the root status to
  authorization-required, and therefore blocks new linked launches. Existing
  processes and immutable snapshots are untouched; profile directories and
  personal CLI homes are not deleted.
- UI copy states the truthful retention contract: Cuckoding has no authorization
  expiry timer and cannot promise years because the provider controls expiry.

### Real-provider evidence

At 2026-09-20 18:05 UTC, the installed pinned Codex and Cursor probes both
returned `authentication_required` for the existing app-owned profiles. The
check selected only non-secret account fields, did not inspect token files, and
launched no paid provider task. Status checks durably recorded their normal
value-free audit events. Authenticated two-project, refresh/restart, concurrent,
and real post-revocation checks remain open, so task 1018 stays in progress.

### Verification in progress

- `rtk env -u CR_PAT mix test test/cuckoding/shared_agent_profile_test.exs test/cuckoding_web/agent_settings_live_test.exs`
  — 6 tests, zero failures. Covers impact aggregation, scoped logout argv/env,
  propagated status, audit event, confirmation copy, and linked-agent counts.

### Final verification for this tranche

- `rtk env -u CR_PAT mix quality` — exit 0 on final run: formatter,
  warnings-as-errors compilation, 265 tests and 10 properties with zero failures,
  Credo over 203 files/3,279 functions with no issues, Sobelow clean, and Hex
  audit with no advisories. A prior full rerun hit the existing concurrent SQLite
  property's transient `database is locked`; the same property and seed passed
  alone, changed-area tests passed, and the final complete gate passed.
- `rtk env -u CR_PAT mix assets.build` — exit 0; Tailwind and esbuild completed.
- `rtk git diff --check` — passed.
- Live browser check at `/settings/agents` rendered the no-TTL explanation,
  one impact section per root account, copyable commands, sign-in status, model
  selection, and no duplicate login cards. Both current real profiles still say
  sign-in required, so the disconnect control correctly remains hidden until a
  profile is connected.
- A follow-up real browser check at 18:16 UTC re-probed both saved profiles;
  each still returned sign-in required. Both adjacent **Copy** controls changed
  to **Copied** and announced `Command copied to clipboard.` through the live
  status region. At an exact 320×844 viewport, `innerWidth`, document width, and
  body width were all 320 px; every add/edit/model/sign-in/copy/check control
  remained in the accessibility tree. The temporary viewport override was reset.
- Scoped changed-line security review found no credential value, token content,
  private key, password assignment, provider output persistence, personal-home
  fallback, or unconfirmed destructive action. Provider command output is discarded.

## 2026-09-20 Cursor Keychain persistence fix

The real Cursor browser authorization completed, but the CLI could not save its
login because the approved app-owned `HOME` has no macOS default keychain. A
read-only check reproduced that boundary: `security default-keychain -d user`
succeeded under the personal HOME and failed under an isolated HOME; setting
`CFFIXED_USER_HOME` did not change the result. No keychain item was read,
deleted, reset, or changed.

XERJ remained unreachable. Direct inspection of the installed pinned Cursor CLI
`2026.09.15-d2fe57e` found its supported
`AGENT_CLI_CREDENTIAL_STORE=file` mode in `src/utils/credential-store.ts` and
the provider implementation in `cli-credentials/dist/index.js`. On macOS that
mode stores refreshable credentials at `~/.cursor/auth.json`, creates the parent
with `0700`, and writes the file with `0600`. No vendor code was copied.

The adapter now selects that mode for login, probes, execution and logout while
retaining the app-owned HOME, run-owned task configuration, fixed empty MCP and
sandbox files, plugin rejection, and personal-home prohibition. Cuckoding does
not read, copy, serialize, display or inject credential values. The browser
login must be repeated before authenticated two-project/restart/concurrency
acceptance can close task 1018.

Verification:

- `rtk env -u CR_PAT mix test test/cuckoding/adapters/cursor_agent_test.exs test/cuckoding/shared_agent_profile_test.exs test/cuckoding_web/live/agent_settings_live_test.exs`
  — 12 tests, zero failures. Login, probe, launch and logout all select the same
  persistent credential mode while preserving account/run path separation.
- Real `cursor-agent status --format json` under the corrected app-owned
  environment returned unauthenticated without a Keychain prompt; no token or
  personal provider state was read.
- `rtk env -u CR_PAT mix quality` — exit 0: 265 tests and 10 properties, formatter,
  warnings-as-errors compile, Credo, Sobelow and dependency audit all passed.
  The two logged fixture crashes are the expected supervisor-restart test.
- `rtk env -u CR_PAT mix assets.build` and `rtk git diff --check` — passed.
- Live browser verification after a server restart showed the Cursor command
  beginning with `AGENT_CLI_CREDENTIAL_STORE='file'`; the personal HOME and
  Keychain are absent from the command.

## 2026-09-20 provider model discovery

Acceptance for this continuation: after a successful shared-agent authorization
check, fetch the provider-account model catalog, persist only validated bounded
picker data, and use it for every linked agent's model dropdown. Authentication
must remain valid when discovery temporarily fails, and editing an agent must not
erase the last catalog.

XERJ remained unavailable at `localhost:9200`. Official Codex app-server
documentation (`model/list`, lines 1122-1155 of the fetched page) defines the
authenticated picker-visible model response and hidden-model behavior. The pinned
Cursor CLI `2026.09.15-d2fe57e`, `2062.index.js` module
`./src/commands/models.ts`, confirms the account-scoped `models` output format.
No provider source was copied. Cuckoding uses its existing direct-process and
shared-profile boundaries, discards raw output/errors, and stores only model IDs,
display labels, discovery status, and count.

Delivered:

- Codex uses the official stdio app-server handshake and `model/list`; Cursor
  invokes `models` with the same app-owned file-credential environment used by
  login, probe, launch, and logout.
- Authorization checks persist a bounded normalized catalog on the root account
  in the same audited status transaction. Linked agents read that root catalog.
  Discovery failure is visible but does not downgrade authenticated status.
- The Agents LiveView offers provider-reported models after refresh, retains
  Runtime default and Custom model ID fallbacks, reports catalog state, and
  preserves catalogs across agent edits.

Focused verification:

- `rtk env -u CR_PAT mix test test/cuckoding/adapters/codex_test.exs test/cuckoding/adapters/cursor_agent_test.exs test/cuckoding/shared_agent_profile_test.exs test/cuckoding_web/agent_settings_live_test.exs`
  — 20 tests, zero failures. Covers protocol/output normalization, unsafe model
  rejection, shared-root persistence, linked reuse, edit preservation, and UI.
- `rtk env -u CR_PAT mix run --no-start -e '...'` called the installed Codex
  0.146.0 app-server with the app-owned profile and returned four normalized
  picker-visible models: GPT-5.6 Sol, Terra, Luna, and GPT-5.5. No credential
  file or raw provider error was read or persisted.
- `rtk env -u CR_PAT mix quality` — final exit 0: formatter, warnings-as-errors
  compile, 267 tests and 10 properties with zero failures, Credo over 203 files
  with no issues, Sobelow clean, and Hex audit with no advisories. The two logged
  fixture crashes are expected supervisor-restart coverage.
- `rtk env -u CR_PAT mix assets.build` and `rtk git diff --check` — passed.
- Live browser verification at `/settings/agents` rendered the refreshed copy,
  accessible model selector, per-root catalog status, and **Check sign-in and
  refresh models** controls. The real saved Codex and Cursor profiles still
  reported sign-in required, so the UI correctly did not claim a fetched catalog.
- Changed-line security review found no credential/token value, raw provider
  output persistence, personal-home fallback, shell interpolation, or hidden-model
  request. Catalog values are bounded and validated before durable storage.

## 2026-09-21 live sign-in and server restart

- Restarted the development Phoenix server on `127.0.0.1:4000`; an HTTP request
  to `/` returned 200. `rtk curl -fsS http://127.0.0.1:4000/health`
  reported database, PubSub, and web endpoint all `ok`. The separate packaged
  menubar app was left running.
- Read only non-secret saved-account metadata and ran each installed CLI's
  status command with its app-owned profile environment. Codex CLI 0.146.0
  reported `Logged in using ChatGPT`; Cursor CLI 2026.09.15-d2fe57e reported
  `isAuthenticated: true`. No credential file or token value was read, no
  provider task was launched, and no account state was changed.
- This clears the immediate sign-in prerequisite, not task 1018 acceptance:
  two-project execution, refresh/revocation, concurrent use, and full scoped
  security checks remain open. No paid run or release claim is inferred.
- Documentation-only change: `rtk git diff --check` passed; no product tests
  were rerun or claimed for the new status evidence.

## 2026-09-21 isolated Codex authorization correction

- Restated acceptance: a saved Codex login must work from the scrubbed run
  environment without personal-home access, remain shared across project runs,
  and never put credential values in Cuckoding data or logs. Task 1018 remains
  in progress until real two-project, refresh/restart/revocation, concurrency,
  path/MCP and UI evidence exists.
- Clean `main` at `9195af6` before `fix/1018-codex-isolated-auth`. The two
  disposable Git fixtures at `/tmp/cuckoding-auth-a.nMknDR` and
  `/tmp/cuckoding-auth-b.TZVwxg` contained only a README. An installed Codex
  0.146.0 invocation against fixture A with the app-owned `CODEX_HOME` and
  isolated `HOME` failed before model work: `failed to load CLI auth from
  keyring: Platform secure storage failure: A default keychain could not be
  found.` The previous personal-shell `login status` was therefore not valid
  execution evidence. No token or credential file was read.
- The [official Codex authentication guide](https://learn.chatgpt.com/docs/auth)
  specifies `cli_auth_credentials_store="file"` in `CODEX_HOME/auth.json` and
  says keyring fails when unavailable. XERJ's local endpoint was unreachable,
  so direct source inspection identified every login/probe/model/launch/logout
  caller. The change selects file mode at all five boundaries, keeps the
  app-owned 0700 profile, and refuses symlinked or group-readable `auth.json`
  without reading its content. The previous keyring credential is untouched;
  the user must sign in again through Agents. Real provider acceptance is still
  open, including the same-user host-process residual risk of file storage.
- `rtk proxy /usr/bin/env -i HOME=/tmp/cuckoding-auth-a.nMknDR ... codex -c
  'cli_auth_credentials_store="file"' login status` returned `Not logged in`,
  confirming file mode works under isolated `HOME` but needs a fresh sign-in.
  `rtk proxy` was used for exact file/instruction reads, the installed CLI and
  long-running server commands where filtered output or wrapper semantics
  would obscure the result. No credential content was printed.
- `rtk test mix test test/cuckoding/adapters/codex_test.exs
  test/cuckoding/shared_agent_profile_test.exs
  test/cuckoding/project_workflow_test.exs
  test/cuckoding/project_onboarding_test.exs` — 24 tests, zero failures.
  `rtk proxy /usr/bin/env -u CR_PAT mix format` and `mix quality` — passed;
  quality ran 270 tests plus 10 properties, warnings-as-errors compile, Credo,
  Sobelow and Hex audit. The two supervisor fixture crashes were expected.
- Restarted only the development Phoenix listener on `127.0.0.1:4000`; the
  packaged shell was not touched. `/health` returned application, database,
  PubSub and web endpoint `ok`. Docs were corrected to retract the prior
  keyring-based acceptance inference. Fresh authenticated execution remains
  the next gate.

## 2026-09-21 provider process-group exit continuation

- Claimed task 1018 on `fix/1018-process-group-exit` from clean `main`. Acceptance
  for this tranche: when a provider CLI exits, its same-group child processes
  must be stopped before durable completion; a normal-exit regression must
  fail without the fix. Preserve start-identity checks, signal audit events,
  and report cleanup failures rather than silently claiming success.
- Real Cursor smoke used one saved app-owned authorization in two disposable
  Git projects. Both read-only runs returned the expected project-specific
  README word and left repositories clean. The separate Codex file-store
  profile still requires a fresh sign-in; this is not full board acceptance.
- Post-smoke inspection found two orphaned Cursor worker servers in the exact
  disposable project directories. After verifying their PID, start time,
  parent, process group, and working directory without printing process argv,
  sent TERM to only those two PIDs and confirmed they exited. An unrelated
  host process had earlier exposed a provider key in its argv; the value was
  not retained or repeated, and rotation remains unverified.
- XERJ was unreachable at localhost:9200. Direct reference inspection of
  Apache-2.0 vibe-kanban at pinned commit
  `735654971bd396aa97b65166955678e4c34f8bf8`,
  `crates/local-deployment/src/container.rs:805` and
  `crates/utils/src/process.rs:5-21`, shows exit-time cleanup of orphaned
  same-group children using the PGID captured at spawn. No source copied;
  Cuckoding must retain its stricter durable event and identity boundaries.
- The focused normal-exit regression failed against the previous runner at
  `local_process_runner_test.exs:139`: the background child still existed after
  `LocalProcessRunner.result/1`. After the fix, the same test passes. A live
  leader is refused by the new exit-only cleanup path, and an exit-time cleanup
  error is now a failed process plus a `process.cleanup_failed` audit event and
  caller error, not a successful result.
- `rtk test mix test test/cuckoding/execution/local_process_runner_test.exs`
  — 9 tests, zero failures. `rtk env -u CR_PAT mix format` — passed.
  `rtk env -u CR_PAT mix quality` — exit 0: warnings-as-errors compile,
  271 tests plus 10 properties, zero failures, Credo over 204 files/3,332
  functions with no issues, Sobelow clean, and Hex audit with no advisories.
  Two plugin supervisor crash-fixture logs were expected test coverage.
- The implementation closes the observed same-group worker leak. It does not
  establish cleanup of a provider child that detached into a separate process
  group before leader exit, nor complete a full authenticated Cuckoding board
  workflow. These remain Phase 10 gates.
- A second pass made process-group inspection fail closed and checks the
  recorded leader identity before each signal. The first full rerun found one
  Credo nesting warning; it was removed without changing behavior. Final
  `rtk env -u CR_PAT mix quality` — exit 0: 271 tests plus 10 properties,
  zero failures, Credo over 204 files/3,335 functions with no issues,
  Sobelow clean, and Hex audit with no advisories.
- `rtk test mix test test/cuckoding/execution/local_process_runner_test.exs
  test/cuckoding/execution/lifecycle_test.exs` — 12 tests, zero failures after
  the fail-closed pass. `rtk git diff --check` — passed. No live provider run was
  repeated while the previously exposed host argv key rotation remains
  unverified.
- Committed the runner/docs/test slice as `3460d7b`, fetched `origin/main`,
  fast-forwarded local `main`, and `rtk git push origin main` advanced the
  remote from `5f3ed9f` to `3460d7b`. The worktree was clean afterward.
  Verified the old loopback development listener's PID, start time, and repo
  CWD, sent only that PID TERM via `rtk proxy /bin/kill -TERM 12360`, confirmed
  port 4000 was free, then restarted with
  `rtk proxy env -u CR_PAT PHX_SERVER=true mix phx.server`. Proxy preserved
  the exact signal command and server stream. `rtk curl -fsS
  http://127.0.0.1:4000/health` reported application, database, PubSub, and
  web endpoint `ok`. The packaged menubar shell was not touched.

## 2026-09-21 saved-agent selector and status UX

- Claimed task 1018 on `fix/1018-agent-selector-status` from clean `main`.
  Acceptance: choosing a saved agent must not open a confirmation before the
  user submits; only runtime-compatible agents should be selectable; a
  connected agent should show a green, textual status and no obsolete
  run-local sign-in command, with a clear re-authorization path. Preserve the
  audited queued-run binding and immutable run snapshot.
- Reproduced the reported native confirmation by clicking **Choose saved
  agent** on queued run `01a0bcd7-0e7d-7df7-8263-a71361f5de57`. No binding
  was submitted or changed. The root cause is `data-confirm` on the wrapping
  form: Phoenix HTML dispatches click handling through ancestors. The same
  pattern exists on the Agents edit form. Current run cards list incompatible
  agents and show run-owned login commands even when reusable agents exist.
- Ponytail 4.10.0 (MIT) full, LiveView, workflow, security-review,
  quality-gates, better-ui, better-writing, and better-accessibility guide a
  native-control, minimal-diff fix. The authorization and deletion boundaries
  remain unchanged.
- Moved confirmation from both forms to their submit buttons, filtered queued
  run choices through the same compatibility check used by the binding service,
  and removed legacy run-local sign-in commands. Connected agents now have a
  green text status; re-authorization remains available on the shared Agents
  page, with its command collapsed until requested. Project settings hides the
  same unnecessary command after authorization. No credentials or run
  snapshots were changed.
- `rtk env -u CR_PAT mix test test/cuckoding/project_workflow_test.exs
  test/cuckoding_web/agent_settings_live_test.exs
  test/cuckoding_web/project_edit_live_test.exs` — 9 tests, zero failures.
  `rtk env -u CR_PAT mix test test/cuckoding/project_workflow_test.exs` — 4
  tests, zero failures after adding the incompatible-account regression.
  `rtk env -u CR_PAT mix format` — passed. First quality attempt stopped at a
  formatting difference; second passed all 271 tests and 10 properties but
  found an alias-order lint issue, both corrected. Final
  `rtk env -u CR_PAT mix quality` — exit 0: warnings-as-errors compilation,
  271 tests and 10 properties with zero failures, Credo clean, Sobelow clean,
  and Hex audit with no advisories. Plugin crash-fixture logs are expected.
- In the actual in-app browser, the exact queued run's native dropdown opened
  without a confirmation and accepted a saved-agent selection. No Connect
  submission was made against the user's run. Agents showed both existing
  saved accounts as Connected with collapsed Re-authorize controls. Updated
  authorization-flow and dashboard docs to match. No migration was needed.
- Follow-up regression on the same task: a connected root account in project
  settings has no sign-in command, shows textual Authorized status, and links
  to Re-authorize agent. `rtk env -u CR_PAT mix test
  test/cuckoding_web/project_edit_live_test.exs` — 4 tests, zero failures.
  `rtk env -u CR_PAT mix quality` — exit 0 again: 271 tests and 10
  properties pass, Credo/Sobelow clean, no retired or advisory packages.

## 2026-09-21 queued-run authentication recovery

- Claimed task 1018 again on `fix/1018-auth-start-recovery` from clean `main`.
  Acceptance: a saved Codex profile without its private file-store credential
  must never appear connected; a failed start check must update the durable
  account observation, name the affected agent, and point to its one-time
  sign-in action without changing the queued run or worktree. A valid saved
  profile must still start without prompting again.
- Reproduced run `01a0bcd7-0e7d-7df7-8263-a71361f5de57`: the browser showed
  both agents Connected and a generic sign-in error. The saved Cursor check
  passed; the saved Codex check returned Sign-in required. A metadata-only
  `rtk proxy /usr/bin/stat` of the exact app-owned Codex `auth.json` path
  returned ENOENT; no credential contents were read or printed. Proxy kept the
  exact stat output. The older green observation predated the switch from
  keyring to the isolated file store, as recorded above. XERJ's loopback node
  was unreachable; direct project source and the previously pinned reference
  corpus were inspected. No peer code was copied.
- The saved Codex readiness check now requires the provider's login result and
  metadata for a regular owner-only credential file in the selected app-owned
  profile. Account projections mask a stale green observation when that file
  is absent. At run start, each distinct saved connection records its fresh
  authenticated/sign-in-required observation and audit event before the run
  transitions; the failure leaves the task and worktree intact. The run page
  names the affected agent and links directly to its Agents sign-in card.
  No credential contents are read, copied, logged, or exposed.
- Reference coding: XERJ was unavailable on loopback; direct Cuckoding source
  was searched. Pinned Hydra `d8ad561...`,
  `electron/agents/AgentManager.ts:300-332`, MIT license, was inspected for
  shared-profile ownership; no peer code was adapted because the existing
  Cuckoding profile and status paths were sufficient.
- Focused check: `rtk env -u CR_PAT mix test
  test/cuckoding/project_workflow_test.exs` — 5 tests, zero failures. The new
  queued-run regression covers a CLI that falsely reports logged-in without
  a file, the named recovery link, durable status/event, queued state and
  retained worktree. Codex and shared-profile tests cover private-file and
  unsafe/missing-file behavior. `rtk git diff --check` — clean.
- Full check: `rtk env -u CR_PAT mix quality` — exit 0; 10 properties and 273
  tests pass, Credo clean, Sobelow clean, Hex audit no advisories. Expected
  fixture crash logs appeared only in the supervisor crash-recovery test.
  `rtk proxy curl -fsS http://127.0.0.1:4000/health` — application, database,
  PubSub and web endpoint all OK; proxy preserved the exact JSON response.
- Browser check on the reported run: after code reload, Cursor remained
  Connected; Codex displayed Sign-in required and its named direct link opened
  the matching Agents card with a copyable one-time sign-in command. The user
  must finish that provider-owned device sign-in and recheck the account;
  live provider refresh/execution acceptance remains open in task 1018.
