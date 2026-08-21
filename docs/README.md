# AgentDesk

AgentDesk is a local-first desktop workspace for running multiple coding agents on the same software project. Each agent works in its own tab and can operate concurrently while a central Elixir/OTP coordinator provides built-in agent-to-agent (A2A) discovery, task delegation, durable messages, artifacts, handoffs, resource leases, and project memory.

`AgentDesk` is a working name and can be changed without affecting the architecture.

## Product goals

- Connect Codex, Claude Code, Cursor Agent, OpenCode, and future CLI or SDK-based agents through provider adapters.
- Show streamed agent activity in independent LiveView tabs.
- Give every agent built-in peer discovery and capability cards.
- Let agents delegate tasks, exchange structured messages, publish artifacts, and create durable handoffs.
- Prevent accidental collisions through leases and isolated Git worktrees.
- Coordinate shared resources such as databases, migrations, Docker services, and ports.
- Keep project state local and recover cleanly after crashes.
- Make project code, documentation, decisions, and agent history searchable with XERJ.
- Preserve the user's existing provider authentication; AgentDesk must not collect provider passwords.

## Default operating model

1. The user opens a Git repository.
2. AgentDesk creates project metadata and a private runtime directory.
3. Each agent session receives a dedicated Git worktree and branch.
4. The agent connects to the local Agent Hub through MCP and automatically registers an internal A2A capability card.
5. Agents discover eligible peers, exchange durable messages, and may delegate tasks through the hub.
6. Before changing a resource, the agent requests a time-limited lease.
7. Activity is normalized into a provider-independent event stream.
8. Completed work is published as artifacts and handed off as a commit, summary, changed-file list, and validation results.
9. Another agent or the user reviews and integrates the commit.

## Technology baseline

- Elixir/OTP and Phoenix LiveView
- ExTauri for the native desktop wrapper and desktop APIs
- SQLite through Ecto for canonical application state
- Phoenix PubSub for live internal events
- Git worktrees for concurrent filesystem isolation
- A built-in internal A2A Hub for discovery, delegation, messages, tasks, artifacts, and handoffs
- A local MCP surface through which provider agents call the A2A Hub and other tools
- XERJ as an optional derived search and long-term memory layer

## Documentation

| File | Purpose |
| --- | --- |
| [PLAN.md](PLAN.md) | Delivery phases, acceptance criteria, and MVP boundary |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Components, processes, data flow, and failure boundaries |
| [AGENTS.md](AGENTS.md) | Repository instructions for coding agents |
| [DB.md](DB.md) | SQLite/Ecto data model and invariants |
| [A2A.md](A2A.md) | Built-in internal agent discovery, delegation, messaging, tasks, and artifacts |
| [PROTOCOL.md](PROTOCOL.md) | Agent Hub messages, MCP tools, leases, and handoffs |
| [PROVIDERS.md](PROVIDERS.md) | Codex, Claude Code, Cursor Agent, OpenCode, and generic provider adapters |
| [UI.md](UI.md) | Desktop information architecture and interaction states |
| [XERJ.md](XERJ.md) | Search, indexing, and memory integration |
| [SECURITY.md](SECURITY.md) | Threat model, permissions, and local security defaults |
| [TESTING.md](TESTING.md) | Test layers and concurrency scenarios |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Bootstrap and local development conventions |
| [DECISIONS.md](DECISIONS.md) | Initial architectural decisions and open questions |
| [docs/SOURCES.md](docs/SOURCES.md) | Primary technical references |

## MVP

The first usable release supports:

- macOS;
- one local project at a time;
- Codex, Claude Code, Cursor Agent, and OpenCode adapters;
- multiple concurrent tabs;
- streamed messages and activity;
- pause, resume, interrupt, and terminate controls;
- automatic internal A2A registration and peer capability discovery;
- transactional task delegation with accept, reject, expiry, and revocation;
- durable direct, task, context, and project messages with acknowledgements;
- structured task artifacts and handoffs;
- agent/task status and direct or broadcast messages;
- exact-file and named-resource leases;
- one Git worktree per agent;
- commits and handoffs;
- crash recovery from SQLite.

XERJ semantic memory, directory/glob leases, automated merge queues, Windows, and Linux are post-MVP unless a Phase 0 spike makes them essentially free.

## Non-goals for the first release

- Building a new foundation model or model gateway.
- Replacing Git, provider authentication, or provider billing.
- Silently auto-merging unreviewed agent changes.
- Treating natural-language messages as enforceable locks.
- Storing canonical coordination state only in Markdown or search indices.
- Exposing any local control endpoint beyond loopback.
- Exposing a public A2A gateway or remote-agent discovery by default.

## Current status

Phoenix LiveView + SQLite application scaffolding is in the repository root (`AgentDesk` / `AgentDeskWeb`), with ExTauri native-shell files under `src-tauri/`. Project open/close, last-project restore, correlation/idempotency/optimistic-lock conventions, and SQLite-backed Agent Cards, delegations, messages, and artifacts are in place. Provider adapters and the Agent Hub MCP surface are next.
