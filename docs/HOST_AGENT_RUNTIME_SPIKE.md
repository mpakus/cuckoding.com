# Host Agent Runtime Spike

## Decision

Cursor Agent `2026.09.15-d2fe57e` on Apple Silicon macOS passed the host lifecycle experiment but initially failed the MVP isolation boundary. It edited and committed only the assigned worktree, emitted structured events and token usage, resumed the same session, and stopped without surviving descendants. It also started a user-global Claude-compatible MCP process and wrote session state under `~/.cursor/projects` because the experiment retained the user's real `HOME` for global authentication despite scoped Cursor and Claude configuration directories and an MCP deny rule.

Task 1006 resolves that retained failure by never exposing the real home: each run uses owner-only `HOME`, `CURSOR_CONFIG_DIR`, and `CLAUDE_CONFIG_DIR` paths and requires a fresh login there. A controlled unauthenticated probe wrote only the scoped Cursor config. The adapter also writes an empty run-owned MCP file and refuses project Cursor CLI, sandbox, MCP, and plugin overrides. This makes Cursor selectable without copying global credentials; a fresh authenticated provider smoke remains release evidence, not an implementation prerequisite.

## Tested environment

| Item | Observed value |
| --- | --- |
| Date | 2026-09-17 |
| Host | Apple Silicon (`arm64`), macOS 27.0 |
| Runtime | Cursor Agent `2026.09.15-d2fe57e` |
| Invocation | `--print --output-format stream-json --sandbox enabled --trust --workspace <WORKTREE>` |
| Authentication | Existing Cursor login; no credential copied into argv, files, or the child environment |
| Requested model | Provider default |
| Reported model | `Auto`; the concrete backing model was not reported |
| Environment | `PATH`, `HOME`, locale, `CURSOR_CONFIG_DIR`, and `CLAUDE_CONFIG_DIR` only |

The installed binary reported `2026.08.11-e8db854` during initial inventory and `2026.09.15-d2fe57e` during the final run without an explicit update command. Adapters must probe the version for every launch and reject versions outside their tested range.

## Effective grant

- Read and write `README.md`.
- Run `rtk`, Git, and the cancellation-only `sleep` command.
- Deny environment-file reads, key/environment writes, web fetch, all MCP calls, destructive/network/VCS-host commands, and extra writable paths.
- Use Cursor's `workspace_readwrite` sandbox with network denied. The emitted shell event confirmed `networkAccess: false` and the disposable worktree as the only additional writable path.
- Keep generated permission, sandbox, and empty MCP configuration under `<RUN_ROOT>/run/agent` and the project-scoped permission/sandbox files in the disposable repository baseline.

Cursor documents project/global permission files, deny precedence, and project-relative path matching in its [CLI permissions reference](https://cursor.com/docs/cli/reference/permissions). Its [sandbox reference](https://cursor.com/docs/reference/sandbox) documents workspace confinement, network-deny configuration, and the paths that remain protected. `CURSOR_CONFIG_DIR` is documented in the [CLI configuration reference](https://cursor.com/docs/cli/reference/configuration).

## Observed lifecycle

| Capability | Result |
| --- | --- |
| Worktree edit | Pass: only `README.md` changed |
| Git commit | Pass: agent committed `5a9a634` in the disposable feature branch |
| Source checkout isolation | Pass: source checkout remained clean |
| Structured output | Pass: JSONL init, messages, tool calls, results, and usage |
| Identity | Pass: PID, PGID, process start identity, and provider session ID recorded |
| Native resume | Pass: same session ID returned `RESUME_OK` |
| Usage | Token counts reported; no provider currency cost reported |
| Cancellation | Pass after signaling every owned descendant process group; CLI exited 130 |
| Orphan check | Pass: no observed PID or PGID survived |
| Global state isolation | Fail: provider wrote workspace trust, transcripts, repo metadata, and logs under `~/.cursor/projects` |
| Plugin isolation | Fail: provider started `~/.claude/plugins/.../mcp-server.cjs` despite `Mcp(*:*)` deny and isolated config directories |

Cursor's [headless documentation](https://cursor.com/docs/cli/headless) describes print mode and streamed JSON. Its [output format reference](https://cursor.com/docs/cli/reference/output-format) defines the observed init, result, session, and usage fields. Its [MCP documentation](https://cursor.com/docs/cli/mcp) confirms that the CLI automatically discovers configured MCP servers; an MCP permission deny prevents calls but did not prevent the observed server process from starting.

## Process-tree finding

The first cancellation implementation signaled only the Cursor CLI's process group. Cursor placed its sandbox shell in a second group, so the shell was reparented to PID 1 and survived until explicitly cleaned up. The corrected runner records the process forest, signals descendant groups before the root group using `INT`, `TERM`, then `KILL`, and verifies every observed PID and PGID is gone. The final run observed separate root and shell groups and left no orphan.

`disableTmpWrite: true` also prevented the user's RTK-enabled shell initialization from creating its temporary state. The final grant allows sandboxed temporary writes. This is compatibility, not permission to persist outside the provider's sandbox.

## Captured artifacts

- Reproducible stdlib-only harness: `spikes/0002-host-runtime/host_runtime_spike.rb`.
- Redacted contract fixture: `test/fixtures/agent/cursor-2026.09.15.stream.jsonl`.
- Disposable evidence root retained locally: `/private/tmp/cuckoding-0002-3jumSj`.
- The fixture excludes hidden reasoning, replaces session/request/call IDs and host paths, and keeps representative public event shapes.

## Earlier provider probes

- Claude Code `2.1.142` emitted a structured init event but returned `authentication_failed`; measured provider cost was `$0`. It remains a launch target once the user authenticates it.
- Codex CLI `0.146.0` is authenticated and supports JSONL, native resume, `workspace-write`, and non-interactive `never` approvals. Its safe sandbox intentionally protects a worktree's `.git` pointer and resolved gitdir, so a safely sandboxed agent cannot satisfy this spike's direct-commit criterion. Official Codex documentation confirms JSONL/resume in [non-interactive mode](https://learn.chatgpt.com/codex/non-interactive-mode) and protected Git paths plus approval behavior in [agent approvals and security](https://learn.chatgpt.com/codex/agent-approvals-security).

## Architecture updates

1. Supervise a process forest, not only the initial process group; runtimes may create independent descendant groups.
2. Treat configured grants and runtime-reported grants as separate facts. Persist both and flag mismatches.
3. A provider adapter is unavailable until config, memory, plugin, MCP, transcript, and authentication writes are inventoried and meet project isolation rules.
4. Denying MCP tool calls is not equivalent to preventing MCP server startup.
5. Keep `HOME` only when required for provider-managed login, and never infer that a custom config directory redirects all provider state.
6. Store requested and reported model identities separately; `Auto` is not a concrete model identity.
7. Prefer host-side VCS operations when a safe runtime sandbox protects Git metadata; never weaken the sandbox solely to let an agent commit.

## Reference coding

The harness applies the process identity, bounded termination, resume, and orphan checks found through XERJ in Hydra commit `d8ad56112c2c3acfb2f65f53b6890f30a25c693c` (`PLAN.md:350-375`, `PLAN.md:501-513`). It uses explicit runtime/session/permission arguments while rejecting the bypass-permission pattern inspected in Agetor commit `eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a` (`src/bun/agents.ts:447-570`).
