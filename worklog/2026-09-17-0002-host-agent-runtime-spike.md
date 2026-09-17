# Worklog — 0002 Host agent runtime feasibility spike

## Metadata

- Date/time (UTC): 2026-09-17
- Task: 0002
- Status: done
- Human/agent owner: Codex
- Branch: `feature/0002-host-agent-runtime-spike`
- Start revision: `1440247`
- Environment: Apple Silicon macOS 27.0, Ruby 3.4.2, Git 2.51.1

## Acceptance criteria restatement

- A benign provider run changes and commits only `README.md` in its assigned disposable worktree.
- The runner records stable PID, process group, process start identity, and provider session ID.
- Cancellation terminates the provider and every observed descendant process group without an orphan.
- Native session resume, structured output, usage, permission mapping, global state writes, and unsupported isolation assumptions are based on observed evidence.

## Context and references

- Read the required architecture, security, execution-environment, adapter, power, testing, and reference-coding specifications.
- XERJ project retrieval: `tasks/phase-00-discovery/0002-host-agent-runtime-spike.md` and `tasks/phase-03-local-workspaces-runner/0302-local-process-runner.md`.
- Hydra `d8ad56112c2c3acfb2f65f53b6890f30a25c693c`, `PLAN.md:350-375` and `PLAN.md:501-513`: PID/start/session identity, bounded termination, resume, and no-orphan exit criteria.
- Agetor `eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a`, `src/bun/agents.ts:447-570`: explicit model/session/resume/permission arguments and prompt option termination. Cuckoding rejects its bypass-permission pattern.
- Checked current official Cursor CLI documentation for headless JSONL, permissions, sandbox configuration, `CURSOR_CONFIG_DIR`, MCP discovery, and resume.
- Checked current official Codex non-interactive and sandbox documentation for JSONL, resume, approvals, and protected worktree Git metadata.

## Provider inventory and selection

- Claude Code `2.1.142`: structured init succeeded, then the run returned `authentication_failed`; reported cost was `$0`. Fixed an empty-stderr harness bug exposed by this probe.
- Codex CLI `0.146.0`: authenticated. Safe `workspace-write` intentionally protects a worktree's `.git` file and resolved gitdir, so direct agent commit cannot satisfy this spike without weakening the sandbox. This becomes a host-side VCS design input.
- Cursor Agent: authenticated and selected for the complete lifecycle measurement. Its version changed from initial inventory `2026.08.11-e8db854` to final observed `2026.09.15-d2fe57e` without an explicit update command.
- OpenCode: user reports it installed, but no executable was found in the current non-login or login shell. Task 0404 owns path resolution and adapter probing.

## Work performed

- Added a Ruby-stdlib-only harness that creates a disposable repository, branch, worktree, run folder, generated grants, lifecycle events, bounded redacted fixtures, and summary evidence.
- Used a scrubbed environment and new process group. Kept provider login in its managed Keychain; no credential was copied to argv, files, or child variables.
- Restricted file tools to `README.md`; allowed `rtk`, Git, and cancellation-only sleep; denied web fetch, MCP calls, common network/destructive commands, environment reads, and credential writes.
- Configured Cursor's workspace sandbox with network denied and no extra writable/readable roots.
- Added native resume, requested/reported model separation, token usage capture, process start identity, source/worktree cleanliness checks, and global Cursor state metadata inventory.
- Replaced root-group-only cancellation with process-forest discovery and descendant-group-first `INT`/`TERM`/`KILL` escalation after a real run proved Cursor creates a separate sandbox shell group.
- Added the capability report, normalized adapter fixture, ADR-021, and matching process-supervision/adapter documentation.

## Observed run evidence

Final disposable evidence root: `/private/tmp/cuckoding-0002-3jumSj`.

- Runtime: Cursor Agent `2026.09.15-d2fe57e`, `arm64`.
- Benign PID/PGID: `78010` / `78010`; start identity `Thu Sep 17 08:58:34 2026`.
- Session: `40102184-dd62-45f1-a919-4ca8584b5866`; native resume returned the same ID and `RESUME_OK`.
- Commit: `5a9a634607fabbe9778a2ea19bb67c6fd285955c`; only `README.md`; source and worktree clean.
- Benign usage: 19,477 input, 678 output, 94,848 cache-read, 0 cache-write tokens. Provider currency cost was not reported.
- Cancellation PID/PGID: `79828` / `79828`; separately grouped shell PGID `80645`; exit `130`; zero surviving observed PIDs or PGIDs.
- Runtime-reported sandbox: workspace read/write, network false, disposable worktree only.
- Global writes: workspace trust, transcripts, repository metadata, and worker logs under `~/.cursor/projects/...`, despite `CURSOR_CONFIG_DIR` pointing inside the run.
- Global process: `~/.claude/plugins/.../mcp-server.cjs` started despite isolated Cursor/Claude config directories and `Mcp(*:*)` deny.
- Result: lifecycle feasibility passed; Cursor is not production-eligible until task 0404 proves complete provider isolation.

## Failed probes retained as evidence

1. Claude authentication failure produced structured output and `$0` cost; no implementation claim was made from it.
2. Cursor with sandbox temp writes disabled broke the RTK-enabled shell initialization; sandboxed temp writes are now allowed.
3. Root-group-only cancellation exited Cursor but left the separately grouped shell reparented to PID 1. The exact group was cleaned up, then the process-forest implementation passed.
4. `CURSOR_CONFIG_DIR` and `CLAUDE_CONFIG_DIR` redirected generated config and local chat databases but did not stop global project transcripts or Claude-compatible MCP discovery.

## Verification

Commands were prefixed with RTK throughout.

- `rtk proxy ruby -w -c spikes/0002-host-runtime/host_runtime_spike.rb` — pass, `Syntax OK`.
- `rtk proxy ruby spikes/0002-host-runtime/host_runtime_spike.rb /private/tmp/cuckoding-0002-3jumSj /Users/mpak/.local/bin/cursor-agent` — pass, exit 0; edit/commit, resume, usage, cancellation, and orphan assertions passed.
- `rtk git diff --check` — pass before documentation closeout.
- `rtk proxy ruby -rjson -e '…' test/fixtures/agent/cursor-2026.09.15.stream.jsonl` — pass, every line parsed as JSON.
- Focused high-risk credential-pattern scan across every changed file — pass, no matches.
- Hidden reasoning/signature field scan of the committed fixture — pass, no matches.
- Final `rtk git diff --check` and staged diff check — pass.

## Security review

- No provider, GitHub, SSH, Keychain, or MCP credential appears in committed code or fixtures.
- `HOME` remains available only because current Cursor login fails under an isolated home. The report explicitly records the resulting global provider writes and plugin process.
- The fixture removes hidden reasoning and redacts the home directory, disposable root, session IDs, request IDs, call IDs, and commit ID.
- Cursor is blocked from production enablement; a tool-call deny is not accepted as proof that an MCP server was not launched.
- The process-forest termination change is required for tasks 0302 and 0404 and is recorded in ADR-021.

## Handoff

Task 0002 is complete. Task 0004 may use the measured process-forest behavior for sleep/wake and power handling. Task 0404 owns Cursor/OpenCode probing and must keep Cursor experimental until the isolation blocker is resolved. ADR-017 launch support remains Claude Code plus Codex.
