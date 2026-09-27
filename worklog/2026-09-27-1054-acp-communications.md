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
