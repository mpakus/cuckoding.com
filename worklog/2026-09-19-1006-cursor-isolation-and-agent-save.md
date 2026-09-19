# Worklog — 1006 Cursor isolation and per-agent saves

## Acceptance criteria

- Cursor uses a run-owned home/config tree and rejects MCP/plugin configuration.
- Cursor authentication is completed and probed in that run-owned tree.
- Every agent card can save or update independently through an immutable project-config revision.
- Focused adapter, domain, and LiveView tests cover success and failure paths.
- Documentation and verification evidence match the implementation.

## Reference coding

- The local XERJ node was unavailable at `http://localhost:9200`; no search result was treated as evidence.
- `docs/HOST_AGENT_RUNTIME_SPIKE.md:3-78` supplies the retained failure evidence: the direct CLI path was safe for worktree lifecycle but reused the real home, wrote global Cursor state, and started a global MCP process.
- Cursor CLI `2026.09.15-d2fe57e` help and the official configuration documentation identify `CURSOR_CONFIG_DIR`; a controlled unauthenticated probe with run-owned `HOME`, `CURSOR_CONFIG_DIR`, and `CLAUDE_CONFIG_DIR` wrote only the scoped `cli-config.json`.
- Official Cursor MCP documentation confirms automatic global/project discovery, so Cuckoding does not expose the user's real home and rejects configured project MCP/plugins instead of treating a tool-call deny as process isolation.

## Verification

| Check | Result |
| --- | --- |
| `rtk cursor-agent --version`, `rtk cursor-agent --help`, `rtk cursor-agent mcp --help`, `rtk cursor-agent status --help` | Pass: installed CLI is `2026.09.15-d2fe57e`; current headless, stream-JSON, sandbox, workspace, resume, and MCP surfaces were re-inventoried. |
| Isolated real `cursor-agent status --format json` with run-owned `HOME`, `CURSOR_CONFIG_DIR`, and `CLAUDE_CONFIG_DIR` | Pass: reported unauthenticated and created only the scoped `config/cli-config.json`; no global login was visible. |
| Real `Cuckoding.Adapters.CursorAgent.probe/1` against that scoped tree | Pass: `available?: true`, `authenticated?: false`, `status: "authentication_required"`; no account fields were retained. |
| `rtk mix test test/cuckoding/project_workflow_test.exs test/cuckoding/walking_skeleton_test.exs test/cuckoding/adapters/cursor_agent_test.exs test/cuckoding/adapters/stable_stubs_test.exs test/cuckoding/project_onboarding_test.exs test/cuckoding_web/project_edit_live_test.exs` | Pass: 34 tests, 0 failures. |
| `rtk mix test test/cuckoding/adapters/cursor_agent_test.exs` | Pass after final plan-mode and isolated-profile checks: 7 tests, 0 failures. |
| `rtk mix credo --strict` | Pass: 188 source files, no issues. |
| `rtk mix quality` | Pass: formatter, unused-dependency check, warnings-as-errors compiler, 10 properties and 230 tests, strict Credo, Sobelow, and Hex audit all passed. The expected crash-worker fixture logs appeared during its restart test. |
| `rtk git diff --check` | Pass. |
| Authenticated real-provider smoke | Not run: the isolated profile intentionally has no global credential. The run UI now directs the user to authenticate that exact run-owned profile; live authenticated completion remains beta evidence. |

## Work performed

- Replaced the Cursor stable stub with a pinned adapter for `2026.09.15-d2fe57e`: scoped auth probe, owner-only generated configuration, runtime sandbox and network deny, empty MCP configuration, streamed-event normalization, reported-token parsing, native resume, and host-runner cancellation.
- Removed the root cause of the retained global leak by setting run-owned `HOME`, `CURSOR_CONFIG_DIR`, and `CLAUDE_CONFIG_DIR` for probe, login, and launch. Global Cursor authentication is deliberately unavailable inside a run.
- Refused project `.cursor/cli.json`, `mcp.json`, `sandbox.json`, and `plugins` inputs plus plugin directories inside the isolated login profile because Cursor automatically discovers them and a permission deny does not prevent server startup.
- Made Cursor a runnable board adapter. Queued run pages list every required run-owned environment path and the exact executable/login subcommand before launch.
- Added `ProjectOnboarding.save_connection/3`, which validates and upserts one connection into a new immutable project configuration revision without requiring unsaved role assignments or rewriting any board/run snapshot.
- Added a Save agent / Update agent action to every connection card while preserving the existing combined agent-and-role save for bulk edits.
- Updated product, flow, UI, adapter, security, execution, testing, plan, beta, decision, and README documentation to match the new boundary.

## Security review

- The adapter never receives the real home and does not copy a token, credential directory, or global runtime configuration. Authentication remains provider-owned inside the run directory.
- `CURSOR_CONFIG_DIR` alone is not treated as sufficient. The real-home and Claude compatibility paths are both replaced, global MCP discovery becomes unreachable, and unsafe project overrides fail before launch.
- Generated directories are mode `0700`; config, sandbox, and empty MCP files are mode `0600`; symlinked configuration roots are rejected.
- `--approve-mcps`, `--force`, `--yolo`, additional directories, and disabled sandbox modes are never passed. Plan stages reduce the allowlist to reads only.
- Provider output remains untrusted, uses a closed event vocabulary, and is recursively redacted before persistence. Unknown event shapes fail closed, hidden reasoning is not mapped, and provider costs are not invented.
- Per-agent saves use the same optimistic revision check and immutable config-version table as bulk configuration. Invalid and stale writes roll back without a partial revision; existing board and run snapshots remain unchanged.
- No credential, secret, API key, global runtime file, provider process, or Cuckoding plugin was added or exposed by this change.
