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

1. Integrate reviewed, explicitly pinned Codex/Claude ACP bridges without
   broadening runtime configuration, authentication or permissions. Confirm
   modern session configuration and usage shapes against those bridges.
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
