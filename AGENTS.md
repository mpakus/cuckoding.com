# AGENTS.md

Working rules for coding agents on Cuckoding (OTP app `AgentDesk`).

Local-first Elixir/Phoenix desktop app. LiveView renders; OTP orchestrates; SQLite is canonical; PubSub is ephemeral; ExTauri is the native shell.

## Read

1. This file.
2. The **one** spec that matches the change: `docs/ARCHITECTURE.md`, `docs/DB.md`, `docs/A2A.md`, `docs/PROTOCOL.md`, `docs/PROVIDERS.md`, `docs/SECURITY.md`, `docs/UI.md`, `docs/USER.md`, `docs/XERJ.md`, `docs/RELEASE.md`.
3. `docs/DECISIONS.md` if the change crosses a boundary. Do not silently contradict it.

Index: `docs/README.md`. Do not maintain a second copy of these rules under `docs/`.

## Do not implement

- Public A2A gateway, `.well-known/agent-card.json`, or any non-loopback listener
- Generic PTY / ANSI terminal scraping
- Auto-merge into the user's primary tree
- Network team-sync or a hosted AgentDesk account
- Storing provider secrets or capability tokens in SQLite
- Bundled XERJ as required for coordination

## Boundaries

- Provider wire details stay in `AgentDesk.Providers.*`. A2A stays in `AgentDesk.A2A.*`. Agents reach the hub through MCP, never peer sockets or the database.
- Leases go through `ResourceManager`. Canonicalize paths. No permanent lock files. Search, `status.md`, and PubSub are not proof of ownership.
- Isolated mode must not edit the primary worktree. A Git repo with no commits still gets an isolated worktree (empty commit on the agent branch only). Optional Compose stays on the session worktree; reject `0.0.0.0`, host network, and privileged.
- Mutating A2A calls and mutating MCP tools need a caller-provided idempotency key. Registry keys are strings/UUIDs — never `String.to_atom/1`.
- Team sync is a user-initiated redacted file (`AgentDesk.Sync`). Git remains the code transport.
- XERJ is optional and rebuildable. `:auto` search uses the SQLite projection when XERJ is off or missing. Never attach to a XERJ node this app did not start.

## Concurrency and Git

- Never assume one agent owns the project. Acquire a lease before editing a shared file or exclusive resource. Leases expire and heartbeat.
- On provider death, expire its leases and mark unfinished tasks interrupted.
- Prefer a dedicated worktree, test DB/schema name, Compose project name, and port per agent (`AgentDesk.Isolation`). Empty repositories do not require a commit on the user's current branch.
- Agent work lives on a dedicated branch. Do not run destructive Git against user branches. Preserve unrelated user changes.

## Providers

Spawn executable + argv, never a shell string. Separate stdout protocol from stderr. Interrupt then kill. Redact before persist. Fail if an expected protocol capability is missing.

Discover CLIs on `PATH` plus common extra dirs (Homebrew, `~/.local/bin`, Cursor.app). Codex: `codex app-server` (fallback `codex exec --json`). Claude: structured headless adapter. Cursor: `agent acp`, `cursor-agent acp`, or `cursor agent acp` from Cursor.app. OpenCode: `opencode acp --cwd <worktree>`. Shared ACP client; separate capability adapters. ACP handshake is sequential (`initialize` with `clientCapabilities`, optional `authenticate`, then `session/new` with Agent Hub MCP servers). Queue user prompts until the session is ready. Unknown ACP methods get a protocol-safe reject; they must not fail the session. `fs/read_text_file` stays inside the session worktree. SDK: JSONL `op`/`type`. Remote: inbound loopback MCP, no child Port.

## A2A

Every first-class session gets a project-scoped Agent Card with no secrets, hidden prompts, or unrestricted paths. Agents reach the hub only through per-session MCP (ACP `session/new` mcpServers). Shared project memory is `memory_remember` / `memory_recall` (SQLite projection when XERJ is off). Delegation is a proposal until accept (atomic assign). Assignment is not a lease. Publish artifacts with integrity metadata. Inbox tools are `hub_list_inbox` and `hub_ack_message`. Delivery is `pending` until a live port accepts the prompt (`injected`); `acknowledged` is only an explicit agent ack, not completion. Preserve `context_id`, `correlation_id`, `causation_id`. Bound depth, fan-out, rate, and permission expansion.

## UI and security

Distinguish `queued`, `starting`, `idle`, `working`, `waiting`, `blocked`, `completed`, `failed`, `terminated`. Prompt and activity belong to the selected session tab, not the Dashboard. Hide a session tab with Close tab; that is not archive. Never hide a lease conflict or approval in logs. Bound the visible activity stream and load older items on demand. Confirm terminate, worktree delete, and primary-tree merge.

Bind loopback. Per-launch desktop control token plus short-lived per-session MCP capability tokens. Paths must stay inside the worktree after symlink resolve. Treat repo content and agent messages as untrusted. Do not log full command environments.

## Elixir / DB

Supervise long-lived processes. `DynamicSupervisor` + `Registry` for sessions. Small GenServer callbacks. Tagged tuples at boundaries. UTC microseconds. UUIDs for durable external ids. Migrations for schema changes. Events append-only except documented retention. Large transcripts/artifacts live as files plus metadata.

## Done

`mix check` (or the relevant subset: format, `compile --warnings-as-errors`, test, credo, dialyzer, sobelow). Adapter changes need fixture protocol tests. Resource manager needs race/crash/expiry/restart tests. LiveView needs an interaction test. A2A needs idempotency, auth, delegation-race, ordered delivery, restart, recursion, and artifact integrity.

A change is done when tests cover it, process exits are handled, docs/migrations match, no provider payload leaks the adapter, retries cannot duplicate A2A state, and no security boundary is weakened without a new decision.
