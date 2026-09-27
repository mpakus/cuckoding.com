# 1054 — ACP communications

Claim task 1054 only, on `feature/1054-acp-communications`, from clean local
main `e333f6a` (four commits ahead of origin). User goal is a communications
rebuild, not an optional demo adapter. Existing app data and historical evidence
remain authoritative and must be preserved.

Acceptance is recorded in the task: shared ACP for all current execution paths
and supported providers, negotiated capabilities, separated bounded protocol
and diagnostics, durable public progress/session identity, cancellation and
recovery, unchanged security/completion boundaries, conformance and integration
evidence, and matching documentation. Feature items remain unchecked until
verified.

Applied Ponytail 4.10.0 (MIT), full mode, plus agent-adapter,
cuckoding-architecture, local-runner, security-review and quality-gates.
Read product, architecture, DB, flow, security and execution-environment
contracts. No conflicting working-tree changes were present.

## Investigation

- Current planning/delivery/board decisions launch provider CLI processes;
  `OutputParser` extracts results from combined redacted process logs after exit.
  Existing `AgentAdapter` and supervised host runner should be reused.
- `rtk xerj search --prefix cuckoding-project-v7 -k 3 'AgentAdapter process session communication'`
  and `rtk xerj search --prefix ref-vibe-kanban-v1 -k 3 'ACP protocol session prompt'`
  could not connect to the local XERJ endpoint. Continue with the pinned peer
  checkout and direct source inspection; no index or service changed.
- Protocol reference: https://agentclientprotocol.com/protocol/v1/overview .
  The protocol is a transport contract, not authority to approve tool access,
  bypass independent review, publish changes or mark tasks complete.

## Verification

### Transport and Cursor checkpoint

Implemented `ACP.Wire` and the supervised `ACP.Client`, the runner's separated
stdio transport, durable prompt reservations, identity-before-prompt storage,
streamed public events, bounded diagnostics, cancellation/verified cleanup, and
typed structured results. Planning/delivery share `Adapters.await_session/2`;
historical log parsing remains available. Cursor now launches native ACP with
its existing run-owned permission/configuration files. Codex/Claude migration
remains pending. No database migration or dependency was added.

Additional observability and RTK-optimization skills were applied for streamed
accounting and the transport-specific RTK regression. Context-window occupancy
does not count as billed tokens. A mode/model selection acknowledgement cannot
invent an observed model. A state-only observation retains identities already
reported by the runtime.

References reviewed (no peer code copied):

- Pinned Apache-2.0 Vibe Kanban `735654971bd396aa97b65166955678e4c34f8bf8`,
  `crates/executors/src/executors/acp/harness.rs:189,339,391,404,419` and
  `client.rs:67`: stdio separation, negotiation and cancellation. Cuckoding
  retains its own supervised process ownership, recorded grants and durable
  events; peer permission auto-approval and thought storage were not adopted.
- [ACP session setup](https://agentclientprotocol.com/protocol/v1/session-setup)
  and [prompt turn](https://agentclientprotocol.com/protocol/v1/prompt-turn):
  protocol v1, capability-gated load, streamed updates and correlated cancel.
- [Cursor native ACP](https://prod.cursor.com/docs/cli/acp): native stdio,
  modes, permission requests and optional blocking extension requests.
- Apache-2.0 bridge source inspected in temporary checkouts:
  `agentclientprotocol/codex-acp` revision
  `bf37821e8f3c1f1e9b6954171855a9e2579cd2c9`, package 1.13.1;
  `agentclientprotocol/claude-agent-acp` revision
  `e6681d2a5734857727352474c8c9aa848f9210ee`, package 0.81.2.
  Both licenses were read. Neither bridge nor its dependencies were installed
  or executed. The Codex bridge's app-server launch/configuration and mode
  overrides, and Claude's SDK/settings/tool hooks, still require validation
  against Cuckoding's pinned runtime versions and grants.

Commands and results:

- `rtk env -u CR_PAT mix test test/cuckoding/execution/local_process_runner_test.exs`
  initially found a malformed `handle_call` return tuple; corrected before the
  combined run. Only a synthetic test canary appeared in that failed test's
  crash diagnostics. Added redacted `format_status/1` on protocol/runner workers.
- `rtk env -u CR_PAT mix test test/cuckoding/adapters/acp/wire_test.exs test/cuckoding/execution/local_process_runner_test.exs`
  passed: 18 tests, seed 779840, before session-client work.
- `rtk env -u CR_PAT mix test test/cuckoding/adapters/acp/client_test.exs`
  initially exposed fixture admission setup and later cleanup/status assertions;
  fixed the fixture's Ready transition, verified failed/exited process cleanup,
  and ensured teardown waits for owned processes. Subsequent runs passed.
- `rtk env -u CR_PAT mix test test/cuckoding/adapters/acp test/cuckoding/execution/local_process_runner_test.exs test/cuckoding/adapters/output_parser_test.exs test/cuckoding/activity_stream_test.exs test/cuckoding/board_task_intake_test.exs test/cuckoding/walking_skeleton_test.exs test/cuckoding/board_control_test.exs`
  passed: 98 tests, seed 493921, before the native Cursor switch.
- `rtk env -u CR_PAT mix test test/cuckoding/adapters/acp test/cuckoding/adapters/cursor_agent_test.exs test/cuckoding/execution/local_process_runner_test.exs`
  passed: 42 tests, seed 510856, after native Cursor integration.
- `rtk env -u CR_PAT mix compile --warnings-as-errors` passed after correcting
  one unused client argument. Changed Elixir files were formatted with
  `rtk env -u CR_PAT mix format` and their explicit paths.
- `rtk env -u CR_PAT mix credo --strict` initially found numeric formatting,
  worker complexity, and later a nested command callback. Corrected those
  findings; the final quality invocation passed.
- `rtk env -u CR_PAT mix quality` first stopped at formatting; the next run
  found the legacy RTK test's command-line-prompt assumption and the nested
  callback. The RTK test now checks ACP prompt preparation and native permission
  configuration independently of legacy CLI argv. Its focused command
  `rtk env -u CR_PAT mix test test/cuckoding/plugins/rtk_test.exs` passed:
  7 tests, seed 428925.
- Final `rtk env -u CR_PAT mix quality` passed: **397 tests, 10 properties,
  0 failures**, seed 895452; formatter, unused dependency check, compiler with
  warnings as errors, Credo, Sobelow, and Hex audit all passed. The deliberate
  plugin-supervisor crash fixture emitted its expected diagnostic output.
- `rtk /Users/mpak/.local/bin/cursor-agent acp --help` passed;
  `rtk /Users/mpak/.local/bin/cursor-agent --version` returned
  `2026.09.15-d2fe57e`.
- An inline `rtk python3 -` initialize-only probe created temporary, empty
  `HOME`/Cursor/Claude configuration directories, passed
  `AGENT_CLI_CREDENTIAL_STORE=file`, and launched the installed Cursor with
  `--sandbox enabled --trust --workspace <temporary-directory> acp` in its own
  process group. It sent protocol version 1 with filesystem/terminal client
  capabilities disabled. The response advertised v1, loadSession, and
  `cursor_login`. Only those non-secret metadata fields were printed. No login,
  prompt or provider task was attempted. Cursor ignored stdin closure and
  required owned SIGTERM (exit 143); this motivated the verified-host-shutdown
  regression. The temporary probe profile was removed after exit.
- `rtk git diff --check` passed before the final documentation additions;
  repeated after those additions and passed.
- `rtk node --test test/task_board_motion_test.cjs` passed: one suite/test,
  state movement, reduced motion, focus preservation and cleanup.
- `rtk python3 -` structural validation checked 36 local documentation targets
  across ten changed Markdown files; all paths and the new ACP anchors resolved.

No RTK proxy exception was needed. No real-provider task acceptance, local-main
integration, remote publication, native bundle, running-build replacement or
application restart is claimed.

## Remaining work

1. Finish bridge conformance against native execution, including authenticated
   structured results, usage, recovery, and packaged/signing provenance.
2. Connect run/board stop to ACP cancellation without creating a lock inversion
   with `RunControl.launch/2`. Current run-level controls still safely suspend
   or terminate the owned process; direct adapter cancellation uses ACP.
3. Complete failure/restart/sleep and follow-up conformance, including approved
   recovery into a new attempt. Add model/configuration-update handling and
   review all provider extension requests.
4. Run authenticated planning/delivery/reviewer/board-controller acceptance,
   then rendered dashboard and packaged-app checks; record each separately.
5. Finish source-aligned documentation, integrated quality gates, and only then
   consider the previously authorized local-main integration and restart.

## Codex and Claude bridge checkpoint

Switched both remaining supported adapters to the shared ACP client. Preserved
native JSON-schema enforcement: the Codex bridge supplies `outputSchema` on
`turn/start`, and Claude forwards its native `structured_output` as a separate
ACP message. Added modern configuration-option selection/observation, rejection
of mode/model drift, explicit recovery requirements, and packaged-artifact
version/hash/regular-file checks. The planning timeout regression now uses an
ACP runtime fixture and still checks persisted progress and the rendered cause.

Pinned npm packages are `@agentclientprotocol/codex-acp` 1.13.1 and
`@agentclientprotocol/claude-agent-acp` 0.81.2. Their published packages differ
from the source checkouts mentioned above; the published Codex read-only preset
actually grants workspace writes. `agent_bridges/harden.mjs` checks exact source
SHA-256 values and applies explicit policy patches, with build versions marked
`+cuckoding.1`. Codex cannot select full access or automatic review and cannot
fall back to a bundled CLI. Claude cannot import project/personal settings or
managed environment into the bridge, and loaded sessions use the current grant.
Native enterprise policy is retained. Package lifecycle scripts and optional
provider binaries are omitted during installation.

The native Codex 0.146.0 app-server accepts neither `--ignore-user-config` nor
`--ignore-rules`; `--strict-config` only rejects unknown config keys. The adapter
instead refuses a project `.codex` path and account config/rules/hooks/plugins
overrides and supplies critical overrides explicitly. Run/account credentials
remain provider-owned and were not read, copied, or exposed.

Standalone macOS bridges are built with Bun 1.3.10 into ignored
`priv/agent_bridges/`; `desktop/build.sh` builds them before the Phoenix release.
Bun normally loads `.env` and `bunfig.toml` even in a compiled executable. The
build disables dotenv, bunfig, package and tsconfig autoload, then executes each
artifact's version command under a minimal environment in a hostile-config
fixture. It retains package notices, the pinned
[Bun license notice](https://raw.githubusercontent.com/oven-sh/bun/bun-v1.3.10/LICENSE.md),
and rebuild inputs. Redistribution/signing evidence remains a separate gate.

Additional inspected sources (published package paths under
`agent_bridges/node_modules/`):

- Codex `dist/index.js:27268,32964,33874,34124,38600,40543`: native spawning,
  permission presets, thread setup, prompts, configuration options, version.
- Claude `dist/settings.js:86`, `dist/session-mode.js:222`,
  `dist/acp-agent.js:4000,6209,6267,6377,6416`, and `dist/index.js:51`: settings,
  modes, native structured result, SDK startup/options, and environment import.
- `rtk /Users/mpak/.local/bin/codex app-server generate-json-schema --out /tmp/cuckoding-1054-appserver-schema`
  confirmed the pinned native sandbox/turn contracts, including read-only
  network denial and workspace-write temporary-directory fields.
- Both bridge Apache-2.0 licenses were inspected. Claude SDK 0.3.280's package
  points to its README/Commercial Terms; generated notices retain that text.
  No SDK source was patched. Bun's runtime/linked-component notice was inspected
  and retained; no public distribution or licensing clearance is claimed.

Verification and corrections:

- `rtk env -u CR_PAT npm install --ignore-scripts --omit=optional --userconfig=/dev/null --registry=https://registry.npmjs.org`
  in `agent_bridges/` created the lockfile: 121 packages installed, 122 audited,
  zero reported vulnerabilities. The later reproducibility command
  `rtk env -u CR_PAT npm --prefix agent_bridges ci --ignore-scripts --omit=optional --userconfig=/dev/null --registry=https://registry.npmjs.org`
  returned the same counts and zero reported vulnerabilities.
- `rtk node agent_bridges/build.mjs` initially found that Codex's version banner
  includes its package name; corrected exact banner validation. Both binaries
  then compiled and passed isolated version probes. After identifying Bun
  autoload defaults via `rtk /Users/mpak/.bun/bin/bun build --help`, rebuilt with
  explicit disabling flags and passing hostile-config checks.
- `rtk node --test agent_bridges/harden.test.mjs` passed all three tests: strict
  source/policy patches and executable selection, native structured-result
  forwarding, and immutable run-owned Claude settings.
- Inline `rtk python3 -` and `rtk node --input-type=module -` probes launched
  owned process groups under temporary empty profiles and minimal environments.
  Both compiled bridges negotiated ACP v1 and exited cleanly. Native Codex
  accepted the enforced app-server configuration and returned ACP auth-required
  (-32000) at session creation. Native Claude created Plan sessions, advertised
  only Plan/DontAsk, selected `claude-sonnet-4-6` using configuration options,
  and reported that selection. Claude used `/usr/bin/false` as an unauthenticated
  helper. No provider prompt was sent; no personal credentials were used.
- `rtk env -u CR_PAT mix compile --warnings-as-errors` exposed separated private
  function clauses; grouped them and formatted changed Elixir sources.
- `rtk env -u CR_PAT mix test test/cuckoding/adapters/acp test/cuckoding/adapters/codex_test.exs test/cuckoding/shared_agent_profile_test.exs test/cuckoding/plugins/rtk_test.exs`
  initially failed one obsolete argv distinction in the shared-profile fixture.
  The expanded 50-test command including `test/cuckoding/adapters/claude_code_test.exs`
  then exposed a missing test helper option in the RTK fixture. Both were fixed.
- The first `rtk env -u CR_PAT mix quality` reached 402 tests and 10 properties
  with one failure: the planning timeout fixture still emitted legacy JSONL.
  Replaced it with an ACP fixture. Its metadata-only Ruby probe needed
  `--disable=gems` to avoid an unrelated inherited-PATH warning corrupting the
  exact version banner. `rtk env -u CR_PAT mix test test/cuckoding/board_task_intake_test.exs:205`
  then passed (one test, nine excluded), seed 807663.
- The first green `rtk env -u CR_PAT mix quality` passed **402 tests, 10 properties,
  zero failures**, seed 793409. Formatter, unused dependency check, compiler
  warnings-as-errors, Credo, Sobelow and Hex audit passed. Expected crash-fixture
  logs and SQLite contention/retry diagnostics appeared without test failures.
- Final review moved large Codex instructions/configuration and output schemas
  into run-owned files; only bounded policy arguments and file paths enter the
  launch environment. A 300 KB instruction regression proves the launch stays
  below 16 KiB. Native instructions reach app-server through thread-start stdio.
  `rtk env -u CR_PAT mix quality` passed again: **403 tests, 10 properties,
  zero failures**, seed 321454, with the same complete quality gates passing.
- `rtk node --test agent_bridges/harden.test.mjs` passed all three tests after
  the file-backed configuration change. `rtk node agent_bridges/build.mjs`
  rebuilt both final executables with passing version/hostile-config checks and
  copied notices/rebuild inputs. A final inline `rtk python3 -` probe confirmed
  ACP v1 initialization and clean exit using Codex's file-backed configuration;
  no prompt was sent.
- `rtk sh -n desktop/build.sh` passed. Inline `rtk python3 -` documentation
  validation checked 32 local link/path targets and anchors successfully.
  `rtk git diff --check` passed after documentation changes.
- After strengthening the final-message fixture, `rtk env -u CR_PAT mix test test/cuckoding/adapters/acp/client_test.exs`
  passed all 20 tests, seed 678162. It verifies that a named structured result
  is separated from an earlier unnamed public message.

No migration, real-provider task acceptance, local-main integration, remote
publication, full native application build, or running-app restart is claimed.
The goal remains active. Next work is board/run cancellation without holding
the launch lock across protocol negotiation, durable process/session linkage,
recovery conformance, and authenticated/native acceptance.

## Run controls and live transport recovery

Acceptance for this increment: Stop must interrupt both negotiation and a live
turn, close durable admission before cancellation, and wait for verified owned
cleanup. Pause/resume must retain the same prompt; protocol callbacks must stay
responsive while admission is paused. Saved sessions/processes must be linked,
late observations must preserve controls, and recovery must verify the live
transport rather than trust a saved provider identifier.

The worktree was clean on `feature/1054-acp-communications` at the start. Continued
the existing task using Ponytail full mode and the adapter, local-runner,
security-review and quality-gates instructions. No dependency, schema, personal
configuration or provider credential changes were needed.

Source review found that both planning and delivery called `adapter.start` inside
`RunControl.launch`; ACP startup held this lock across every negotiation response.
The protocol client also waited synchronously for admission before prompting,
which could prevent it from handling cancellation. Startup now returns after
local process creation. The saved session is bound to its durable process record
before initialization; negotiated identity is persisted before the prompt.
Protocol admission tries the existing lock without blocking and retries at the
existing 100 ms cadence. The client remains responsive to Stop.

Run/board Stop closes durable admission, asks the registered ACP owner to cancel,
and retains the host runner's verified cleanup. Paused input has a distinct
response; one bounded negotiation request waits for verified process resume.
Stopping paused work does not send CONT. Terminal outcome/event writes share a
transaction; observation projections read current state inside their transaction
and retain paused/cancelled state. Registry ownership is released after cleanup
and terminal persistence, before the next stage is allowed to start.

All three adapters' recovery callbacks now require the same live protocol client,
saved session, active worker and verified recorded process identity. This never
loads/replays a prompt. Full application restart and physical sleep acceptance
remain separate work.

Reference review:

- Reused this repository's `RunControl`, `EventStore`, process registry and
  `LocalProcessRunner` signal/identity checks; no parallel control framework.
- `rtk xerj search --prefix ref-hydra-v1 -k 3 'agent session recovery process resume'`
  could not reach the loopback XERJ node. Used the pinned local source instead.
- Hydra `electron/agents/AgentManager.ts:300` restores saved session metadata with
  no live process and an empty initial prompt. Its MIT license was inspected;
  `rtk git -C /Users/mpak/.local/share/cuckoding/reference-code/hydra rev-parse HEAD`
  confirmed `d8ad56112c2c3acfb2f65f53b6890f30a25c693c`. No code was copied.
  Cuckoding additionally requires durable ownership and live process verification.
- Checked official ACP session/prompt documentation. Capability-gated session
  loading is distinct from reconnecting a live client; cancellation still needs
  verified host cleanup. A2A remains outside this local communication task.

Verification so far:

- `rtk env -u CR_PAT mix test test/cuckoding/adapters/acp/client_test.exs test/cuckoding/run_control_test.exs`
  initially returned 25 tests, four failures: tests still expected negotiated
  identity from synchronous startup, and one loop reused a now-failed bound
  session. Updated expectations to durable observed identity and separated the
  incompatible-negotiation cases. This failing run also emitted SQL sandbox
  teardown diagnostics from the interrupted fixture.
- `rtk env -u CR_PAT mix test test/cuckoding/adapters/acp/client_test.exs test/cuckoding/run_control_test.exs test/cuckoding/execution/local_process_runner_test.exs`
  passed **44 tests**, seed 875509.
- `rtk env -u CR_PAT mix test test/cuckoding/adapters test/cuckoding/run_control_test.exs test/cuckoding/execution/local_process_runner_test.exs`
  passed **93 tests**, seed 435647. New real-subprocess fixtures exercise stalled
  initialization, live cancellation, pending paused negotiation, paused admission,
  session/process linkage, cancellation preservation and live recovery without
  prompt replay. These remain protocol fixtures, not provider acceptance.
- Changed Elixir files were formatted with `rtk env -u CR_PAT mix format`.
- Final quality and documentation validation results are recorded below.

Quality iteration:

- The first `rtk env -u CR_PAT mix quality` passed **409 tests and 10 properties**,
  seed 682581, then failed Credo on nesting, aliases and a simplified `with`.
  Reused the existing launch-state helper, flattened the session-binding/test
  helpers, and aliased the ACP client. `rtk env -u CR_PAT mix credo --strict`
  then passed with no issues.
- Added ownership/path and orchestration-owner-loss regressions. A subsequent
  `rtk env -u CR_PAT mix test test/cuckoding/adapters/acp/client_test.exs --seed 0`
  was mistakenly launched while `mix quality` was running (seed 115836), against
  the same test database. This produced database-busy failures. Both owned test
  processes were interrupted; neither run is passing evidence. The focused run
  also exposed a fixture that reused a run already blocked by its first expected
  failure; split the model/path cases into separate fixtures.
- Inline `rtk python3 -` checked **18 local documentation links and anchors** in
  the changed README/runtime/architecture documents. `rtk git diff --check`
  passed at that checkpoint.
- The clean final `rtk env -u CR_PAT mix quality` passed **412 tests and 10
  properties**, zero failures, seed 966543. Formatter, unused-dependency check,
  warnings-as-errors compiler, Credo, Sobelow and Hex audit all passed. Expected
  deliberate plugin-crash fixture logs appeared; no database-busy failures.
- `rtk node --test test/task_board_motion_test.cjs` passed its motion,
  reduced-motion, focus, ordinary-update and cleanup check.
- Read-only PID/start-identity/executable/cwd inspection found a paused ACP
  fixture group left by the interrupted test command (group 26387, started
  September 27 at 02:37:14 local time). Verified its two members were Ruby
  processes in the exact `cuckoding-acp-135106/worktree` fixture, then applied
  INT/TERM/KILL without CONT and verified zero remaining group members. Two
  unrelated older run-control fixtures from September 24 were left untouched.
  No application or provider process was stopped.

No real provider task, application rebuild/restart, main integration, or remote
publication is claimed by this increment. Task 1054 remains in progress.


### Native compatibility, recovery, and packaging checkpoint

Acceptance for this increment: refuse lost ACP ownership without replay; preserve
historical terminal sessions; run real structured turns with the saved provider
identities; preserve policy/model choices; verify the product planning and board
paths; retain explicit failed-attempt evidence and clean up owned processes.
The task remains 1054. No new orchestration framework, model substitution, global
provider configuration edit, credential copy or A2A service was introduced.

Startup/wake inspection now consults the live ACP registry owner as well as the
recorded PID/start identity. Durable process-start and binding events identify
protocol processes, including the pre-binding crash window. A surviving process
without that owner blocks as `agent_transport_missing`; active attempts/sessions
need attention, completed/cancelled session history remains unchanged, and no
replacement attempt is launched. A live simulated wake gap retains one prompt.

Real runtime checks found and fixed three compatibility problems:

1. Codex creates plugin caches during account discovery. Block plugin loading
   explicitly with both `features.plugins=false` and `features.remote_plugin=false`,
   while leaving provider caches intact. Native `features list` confirmed the
   flags are distinct. Keep apps/hooks/subagents disabled.
2. Upstream codex-acp adds `features.cwd_relative_turn_diffs`, unsupported by
   Codex 0.146.0. The exact-hash patch omits that table and preserves Cuckoding's
   feature overrides. The bridge is now `1.13.1+cuckoding.2`; Claude remains
   `0.81.2+cuckoding.1`.
3. Cursor's CLI aliases differ from its canonical ACP model IDs. Pass the saved
   alias through native `--model`, retain the reported advertised ID for ACP
   selection/drift checks, and store requested/observed models separately. The
   native CLI rejected an invalid alias before a prompt. No guessed mapping or
   fallback model is used.

A complete board attempt then found Codex's native account config had gained a
repository trust entry. It contained only a `projects` table, with no model or
execution options. A bounded strict validator accepts only the native absolute
path/trust-level table format in a regular file. Extra settings, MCP tables,
oversized files, and symlinks still fail closed. Existing trust entries are not
modified or deleted. Rules/hooks and project `.codex` remain refused.

Permission activity now retains bounded, redacted public tool title/kind while
excluding raw arguments. The run-page failure explains the approval request
and preserved evidence instead of a generic planning failure.

Source/reference review reused the existing recovery/event/adapter boundaries
and the prior pinned Hydra comparison. Codex bridge source was inspected at
`dist/index.js:33969` (session config), `:33983` (feature override), and `:34413`
(diff-path helper); SHA-pinned Apache-2.0 source is patched, not approximated.
The official [Cursor ACP documentation](https://prod.cursor.com/docs/cli/acp)
and [CLI parameters](https://cursor.com/docs/cli/reference/parameters) were
checked against native behavior. The native Codex feature inventory and generated
app-server schema were used rather than assuming current upstream flags apply
to the pinned binary.

#### Authenticated evidence (isolated data)

Temporary harnesses live under `/tmp/cuckoding-1054-*.exs`. They use separate
SQLite databases and tiny Git repositories, app-owned existing sign-ins, the
production adapters/client/runner and real provider prompts. They do not alter
the user's application database or personal provider config. Provider-owned
caches/trust metadata are retained. Raw ACP frames/thoughts were not saved.

- `rtk env -u CR_PAT MIX_ENV=test mix run --no-start /tmp/cuckoding-1054-native-probe.exs /tmp/cuckoding-1054-native-codex-4 codex`
  passed: Codex 0.146.0, requested/observed `gpt-5.6-luna`, exact README title
  structured output, persisted session identity, public tool activity,
  `end_turn`, exit 0, clean worktree and verified empty owned process group.
- `rtk env -u CR_PAT MIX_ENV=test mix run --no-start /tmp/cuckoding-1054-native-probe.exs /tmp/cuckoding-1054-native-cursor-2 cursor`
  passed: Cursor 2026.09.15-d2fe57e, requested `grok-4.7-high`, observed
  `grok-4.7[context=256k,reasoning_effort=high,fast=true]`, exact output and clean
  worktree. Cursor ignored stdin closure; bounded host shutdown verified cleanup
  and retained the real exit 130 alongside successful ACP `end_turn`.
- `rtk env -u CR_PAT MIX_ENV=test mix run --no-start /tmp/cuckoding-1054-workflow-probe.exs /tmp/cuckoding-1054-native-workflow-3`
  completed real Codex planning with one validated proposal. Cursor proposal
  review halted on tool approval. The original proposal remained unchanged.
- `rtk env -u CR_PAT MIX_ENV=test mix run --no-start /tmp/cuckoding-1054-review-probe.exs /tmp/cuckoding-1054-native-workflow-3 01a0e1e3-e7d2-7d2e-bd5c-45459075b9f0`
  exercised an explicit new review attempt. It again stopped on a shell request,
  now with a safe public title (`wc`, `od`, and Git inspection). This is permission
  refusal evidence, not a passing review or permission expansion.
- `rtk env -u CR_PAT MIX_ENV=test mix run --no-start /tmp/cuckoding-1054-board-probe.exs /tmp/cuckoding-1054-native-workflow-3 01a0e1e3-e7d2-7d2e-bd5c-45459075b9f0`
  created a separate one-task batch with fresh Codex sessions for every role.
  Controller, specification and implementation passed; the pre-review config
  guard correctly halted on the newly created native trust entry.
- After the strict trust-only fix,
  `rtk env -u CR_PAT MIX_ENV=test mix run --no-start /tmp/cuckoding-1054-board-retry.exs /tmp/cuckoding-1054-native-workflow-3 01a0e1e7-b94f-70ba-934f-0674f6e3cb50`
  used the normal board Retry command and reached **Done**, including independent
  review, automatic local completion and the final Speculator decision. The
  failed attempt remained. Read-only SQLite/Git/process checks verified main
  unchanged, only README changed in the reviewed commit, one exact acceptance
  line, original heading retained and **all ten recorded process groups gone**.
  No push, PR, merge or knowledge publication occurred in this acceptance project.

Early harness runs failed before provider prompts on a wrong task attribute,
a syntax error, duplicate role insertion and a missing disabled Power.Manager.
Those harness issues were corrected; they are not passing evidence. Earlier
native probes surfaced the plugin cache, unsupported flag and Cursor alias
issues above. No approved Claude authentication helper/account was available;
its existing bridge/native negotiation evidence is not an authenticated turn.

#### Verification

- `rtk env -u CR_PAT mix test test/cuckoding/reconciler_test.exs test/cuckoding/adapters/acp/client_test.exs test/cuckoding/execution/lifecycle_test.exs test/cuckoding/power/manager_test.exs`:
  **46 tests, 1 property**, zero failures, seed 752573.
- `rtk env -u CR_PAT mix test test/cuckoding/adapters/acp/client_test.exs test/cuckoding/adapters/cursor_agent_test.exs`:
  **38 tests**, zero failures, seed 335185.
- `rtk env -u CR_PAT mix test test/cuckoding/board_task_intake_test.exs test/cuckoding/adapters/acp/client_test.exs`:
  **40 tests**, zero failures, seed 945066.
- `rtk env -u CR_PAT mix test test/cuckoding/adapters/codex_test.exs test/cuckoding/shared_agent_profile_test.exs`:
  **16 tests**, zero failures, seed 572307, including trust-only metadata,
  rejected extra settings/symlinks/oversize and retained provider caches.
- First full quality pass: **416 tests, 10 properties, one failure**, seed 609660.
  Changing the native Cursor fixture scenario broke the timeout fixture's exact
  replacement. Corrected the fixture selection. A new run-page failure assertion
  initially used a queued run, which cannot render a blocked-run panel; corrected
  the setup to start that run before recording its failure.
- Final `rtk env -u CR_PAT mix quality`: **417 tests, 10 properties, zero
  failures**, seed 165640. Format, dependency checks, warnings-as-errors compile,
  Credo, Sobelow and Hex audit passed. Expected plugin-crash fixture logs appeared.
  Native harnesses used their own databases; no test-database overlap occurred.
- `rtk node --test test/task_board_motion_test.cjs agent_bridges/harden.test.mjs`:
  **4 checks passed**, including motion/reduced-motion/focus and bridge policy.
- `rtk node agent_bridges/build.mjs` rebuilt both standalone bridges and passed
  the hostile Bun configuration/environment canaries.

Packaging review found signing would change bridge hashes and that hardened Bun
executables require the existing JIT entitlement. `desktop/sign.sh` now verifies
pre-signing hashes, signs the bridges with that entitlement, refreshes hashes
before sealing the app, and the release verifier checks the packaged manifest.

- `rtk proxy env -u GEM_HOME -u GEM_PATH PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/ruby desktop/release_metadata_test.rb`:
  **7 tests, 20 assertions**, zero failures, seed 49334. Covers stale hashes,
  post-signing refresh and symlink refusal.
- Copies of both real compiled binaries under
  `/tmp/cuckoding-1054-bridge-signing-1` were signed with
  `rtk /usr/bin/codesign --force --options runtime --entitlements desktop/entitlements/beam.plist --sign - <copied-bridge>`.
  The verifier rejected stale hashes, refreshed and verified signed hashes;
  both signed binaries returned their exact pinned versions in an empty
  environment. This is ad-hoc signing evidence, not Developer ID/notarization.
- `rtk sh -n desktop/sign.sh desktop/build.sh` passed.
- RTK proxy exceptions use the repository's sterile system-Ruby invocation and
  preserve exact Ruby test/signing-helper output; no product command was wrapped.

No app rebuild/restart, local-main integration or remote publication is claimed
at this checkpoint. Packaging/build integration, rendered checks and the final
scope audit remain before task completion; physical sleep and authenticated
Claude acceptance are recorded separately from fixture/local provider results.

Checkpoint structural validation: inline `rtk python3 -` validated **28 local
documentation links/anchors**; `rtk git diff --check` passed.


### Packaged build and visible tool descriptions

`eb74ba9` checkpoints the native/recovery fixes above. The first
`rtk env -u CR_PAT ./bin/dev.build` passed: bridge install/audit (zero
vulnerabilities), bridge policy tests and standalone builds, production
assets/compile/release, Ruby metadata tests (7/20), restart tests (6/98), release
promotion checks, Rust tests (10), fmt/Clippy, Tauri app packaging and sterile
release verification. The verifier confirmed bridge integrity, one-time shell
and browser handshakes, authenticated page rendering, graceful shutdown with no
descendants, crash/safe-mode handling and update snapshot/rollback. No app restart
had occurred during that build.

Final UI-path inspection found activity cards render public summaries, not
arbitrary metadata. ACP tool titles are now included in that summary and redacted
there as well, so the retained approval request is actually visible. The focused
`rtk env -u CR_PAT mix test test/cuckoding/adapters/acp/client_test.exs test/cuckoding/activity_stream_test.exs`
result and final rebuild are recorded below. This keeps the existing activity
component and adds no new UI state or controls.

The focused activity/client run passed **36 tests**, zero failures, seed 92374.
Native computer-use inspection by app name and bundle path timed out; no rendered
native-menu/browser interaction is claimed from those attempts. The sterile
release's authenticated HTTP render and LiveView regressions are separate evidence.

Final post-title `rtk env -u CR_PAT mix quality` passed **417 tests and 10
properties**, zero failures, seed 826375, with all formatter/compiler/static
gates passing. Two SQLite transaction-busy messages were retried successfully;
no overlapping test process was running.


### Completion audit and local integration

All nine task criteria are now checked against the source and evidence above.
Planning/proposal review and delivery/controller stages share `await_session`;
explicit continuations use the same client and capability-gated session loading
in a new authorized attempt. ACP never changes host admission, review, completion
or release authority. No historical failed run was rewritten or retried in the
user's application database.

- Runtime code checkpoint: **60267f5** (`fix(activity): show redacted ACP tool descriptions`).
- Final `rtk env -u CR_PAT ./bin/dev.build` passed all bridge, Ruby, Rust,
  production compile, packaging and sterile-release checks again. The final
  verifier completed at 2026-09-27 08:25:34 UTC, including packaged bridge hashes,
  authenticated HTTP rendering and no-descendant shutdown/recovery checks.
- `rtk git switch main` and
  `rtk git merge --ff-only feature/1054-acp-communications` integrated all five
  ACP commits locally. No conflicts or user changes were present. No push.
- `rtk ./bin/dev.restart` gracefully stopped the previously owned shell PID 54421
  and its release, verified cleanup, then opened the chosen bundle once. It
  reported healthy **http://127.0.0.1:49242**. A pre-existing Ruby warning noted
  a world-writable DBngin PATH entry; no shell PATH setting was changed.
- Read-only PID/start/executable inspection verified exactly one new shell,
  **65202**, and release child **65284**, both started September 27 at 03:25:59
  local time. `rtk lsof -nP -a -p 65284 -iTCP -sTCP:LISTEN` showed only
  `127.0.0.1:49242`. A direct public `/health` read returned HTTP 200, status ok,
  application cuckoding 0.1.0.
- The existing database retained the same counts before and after restart:
  three blocked runs, one done, one queued. No schema migration was added.
- `rtk proxy /usr/bin/ruby --disable=gems desktop/bridge_manifest.rb desktop/src-tauri/target/release/bundle/macos/Cuckoding.app/Contents/Resources/release verify`
  passed against the actual app. Its ACP client BEAM hash matches the verified
  release (`f714177b7eb27677da10807a487e810d15a18810d8073c668a3672d137271534`).
  The raw compile artifact initially differed because release assembly strips
  debug chunks. A direct `rtk elixir -e` `:beam_lib.md5` comparison confirmed the
  compiled/release code identity matches. A prior `MIX_ENV=prod mix run --no-start`
  comparison was refused for missing production DB configuration; no database
  or runtime was started by that failed check.

Task 1054's communication implementation and requested local integration/restart
are complete. Real Cursor approval refusal, unavailable authenticated Claude,
physical sleep, interactive native/browser inspection and Developer ID/public
release gates remain explicitly distinct from the passing automated, isolated
provider and development-bundle evidence. No A2A service or remote publication
was introduced. Later documentation-only completion bookkeeping does not require
another rebuild of the verified runtime code.

Completion documentation validation: **39 local links/anchors** checked by
inline `rtk python3 -`; `rtk git diff --check` passed. All nine task acceptance
items have implementation and verification evidence; remaining external checks
are named separately rather than counted as passes.

### Continuation: current runtime and browser handoff

Continued task 1054's remaining native acceptance check on September 27. Scope:
verify the running build's ownership and health, inspect the existing browser,
and try the normal menu-bar authentication flow. Implementation criteria remain
complete; this follow-up cannot establish a new provider-workflow result.
Ponytail 4.10.0 (MIT), quality-gates and menubar-shell guidance remain applied.

The checkout began clean on local main at `5320013`, ahead of origin/main by ten
commits. Read-only runtime inspection reused the existing restart helper:

```sh
rtk ruby --disable=gems -r json -e 'load "./bin/dev.restart"; s = DeveloperRestart.processes; shells = s.select { |p| File.basename(p[:executable]) == "cuckoding-shell" }; rows = shells.map { |p| {shell: p, releases: s.select { |c| c[:parent] == p[:pid] && File.basename(c[:executable]) == "beam.smp" }.map { |c| c.merge(healthy_port: DeveloperRestart.healthy_port(c)) }} }; puts JSON.pretty_generate(rows)'
```

It confirmed the same single development shell PID 65202 and owned release PID
65284, start identity September 27 at 03:25:59 local, and healthy loopback-only
port 49242. An initial `-r ./bin/dev.restart` probe failed because Ruby's require
does not load that nonstandard extension; explicit `load` succeeded without
invoking the restart entry point. No processes were restarted or terminated.

Computer-use inspection of Chrome found the original planning-failure page still
open on old port 52623, showing the historical 04:48:30 UTC failure. A separate
tab at the current runtime's root redirected to `/unauthorized`, confirming that
this browser needs the normal shell-issued session. The temporary tab was closed
and the original run page preserved.

Selecting Cuckoding by bundle identifier was ambiguous because multiple local
builds share it. Selecting the verified running bundle by its exact path and
trying the macOS menu-bar surface both returned computer-use error `-10005:
timeoutReached`. Interactive authenticated dashboard acceptance remains
unverified. No private token extraction, authentication bypass, run retry or
permission change was attempted. The user can continue through the running
Cuckoding menu-bar icon and its Cuckoding dashboard action.

This follow-up changes only the worklog. `rtk git diff --check` passed; inline
`rtk python3 -` verified the helper/task paths, unique follow-up section and
explicit unverified UI boundary. Claims were reviewed against the tool results.
The earlier automated and real provider results retain their original scope.
No new runtime build is needed.
