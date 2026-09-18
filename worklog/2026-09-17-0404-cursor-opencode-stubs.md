# Worklog — 0404 Cursor Agent and OpenCode stubs

## Acceptance criteria

- Cursor Agent and OpenCode are probed from current installed binaries rather than assumed from desktop-app presence or old documentation.
- Any runtime that cannot meet run-scoped state, plugin, credential, and lifecycle boundaries remains non-selectable and fails every operational callback safely.
- The UI visibly explains why each stub cannot be selected for a stage.

## Reference coding

- Project XERJ search: `Cursor Agent adapter stream-json sandbox config resume usage OpenCode adapter`.
- Pinned Hydra MIT search: `Cursor OpenCode provider session resume headless`; its provider model confirms only launch/resume capability and is not sufficient evidence for Cuckoding's isolation boundary.
- The accepted runtime spike at `docs/HOST_AGENT_RUNTIME_SPIKE.md:3-8,34-50,70-78` is authoritative: Cursor `2026.09.15-d2fe57e` passed lifecycle mechanics but wrote user-global state and started a user-global MCP process, so task 0404 must keep it unavailable.
- Current official Cursor CLI configuration, permissions, sandbox, headless, and output-format documentation confirms the observed binary surface and `CURSOR_CONFIG_DIR`, but does not provide a switch that prevents the spike's global plugin/state behavior.
- Current official OpenCode CLI documentation defines `opencode run`, JSON events, `--pure`, and run-scoped config environment variables; no OpenCode CLI binary is installed on this host, so the desktop app is not treated as CLI support.

## Verification

| Check | Result |
| --- | --- |
| `rtk agent --version`, `rtk agent --help`, `rtk cursor-agent --version`, `rtk cursor-agent --help` | Pass: both commands resolve to Cursor Agent `2026.09.15-d2fe57e`; current headless, stream-JSON, sandbox, model, resume, and force surfaces were inventoried. |
| Sanitized global and isolated `agent status --format json` probes | Global auth is available; a fresh `CURSOR_CONFIG_DIR` is unauthenticated. Only key names and a boolean were printed; account fields were discarded. |
| `rtk mix run ... CursorAgent.probe/OpenCode.probe` | Pass: application probes report Cursor installed/authenticated but `available?: false` with `unsupported_global_state_isolation`; OpenCode reports `available?: false` with `cli_not_installed`. |
| OpenCode filesystem/package probe | `/Applications/OpenCode.app` is desktop version `1.18.21`; `opencode` is absent from `PATH`, no Homebrew CLI prefix exists, and the GUI binary is not treated as the documented CLI. |
| Project and pinned Hydra XERJ searches | Pass: retrieved the accepted Cursor rejection and peer launch/resume patterns before implementation. |
| `rtk mix test test/cuckoding/adapters/stable_stubs_test.exs test/cuckoding_web/status_live_test.exs` | Pass: 5 tests, 0 failures. |
| `rtk mix quality` | Pass: 8 properties, 87 tests, 0 failures; warnings-as-errors compilation, strict Credo with no findings, Sobelow, and dependency audit passed. |
| `rtk git diff --check` | Pass. |
| Real provider smoke | Not run: Cursor is explicitly ineligible after the retained isolation failure; OpenCode CLI is absent. Neither limitation is reported as passing conformance. |
| XERJ refresh | Not retried: generation 22 remains sealed behind the 95% disk flood-stage watermark; generation 21 remains the committed project index. |

## Work performed

- Added minimal Cursor Agent and OpenCode implementations of the shared adapter behaviour that probe real install/version/auth facts but advertise zero usable adapter capabilities and reject every operational callback with a classified, non-retryable availability error.
- Preserved the distinction between installed software and a supported adapter: Cursor's detected CLI remains unavailable; the OpenCode desktop app does not count as an installed OpenCode CLI.
- Added a small runtime catalog and an accessible LiveView status/selection component. Both radio controls are disabled, labeled by a fieldset/legend, and linked to visible plain-language warnings.
- Updated the implementation plan and adapter, security, development, and testing documentation to reflect the evidence-backed stub decision.

## Security review

- Cursor remains blocked because the retained spike observed global transcript/repository writes and a user-global MCP child despite scoped configuration and an MCP deny. Cuckoding does not reinterpret a tool-call deny as process-start isolation.
- Probes parse only the exact version and authentication boolean needed for availability. Account data returned by Cursor is neither copied into the probe struct nor logged by the implementation.
- Stub callbacks cannot render config, start processes, decode provider events, resume sessions, or report usage. The catalog independently marks both entries non-selectable, and the UI renders disabled native controls rather than relying on color or prose alone.
- OpenCode desktop metadata is public package metadata, not authority to launch its Electron executable as a CLI. Future enablement requires an installed CLI plus the full run-scoped config, plugin, credential, event, cancellation, and recovery conformance suite.
- No credential, global runtime directory, provider process, plugin, MCP server, network grant, or source mutation is introduced by this task.
