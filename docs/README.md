# Cuckoding

Cuckoding is a local-first desktop workspace for running multiple coding agents on the same software project. Each agent works in its own tab and can operate concurrently while a central Elixir/OTP coordinator provides built-in agent-to-agent (A2A) discovery, task delegation, durable messages, artifacts, handoffs, resource leases, and project memory.

OTP modules remain `AgentDesk` / `AgentDeskWeb`.

## Product goals

- Connect Codex, Claude Code, Cursor Agent, OpenCode, and future CLI or SDK-based agents through provider adapters.
- Show streamed agent activity in independent LiveView tabs.
- Give every agent built-in peer discovery and capability cards.
- Let agents delegate tasks, exchange structured messages, publish artifacts, and create durable handoffs.
- Prevent accidental collisions through leases and isolated Git worktrees.
- Coordinate shared resources such as databases, migrations, Docker services, and ports.
- Keep project state local and recover cleanly after crashes.
- Share coordination state across machines with an explicit redacted sync bundle.
- Make project code, documentation, decisions, and agent history searchable with XERJ.
- Preserve the user's existing provider authentication; AgentDesk must not collect provider passwords.

## Default operating model

1. The user opens a Git repository.
2. AgentDesk creates project metadata and a private runtime directory.
3. Each agent session receives a dedicated Git worktree and branch. Isolation templates stay in the app-owned session directory, never the primary tree.
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
| [USER.md](USER.md) | User manual for people running the desktop app |
| [PLAN.md](PLAN.md) | Delivery phases, acceptance criteria, and MVP boundary |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Components, processes, data flow, and failure boundaries |
| [AGENTS.md](../AGENTS.md) | Working rules for coding agents (canonical; not duplicated here) |
| [DB.md](DB.md) | SQLite/Ecto data model and invariants |
| [A2A.md](A2A.md) | Built-in internal agent discovery, delegation, messaging, tasks, and artifacts |
| [PROTOCOL.md](PROTOCOL.md) | Agent Hub messages, MCP tools, leases, and handoffs |
| [PROVIDERS.md](PROVIDERS.md) | Codex, Claude Code, Cursor Agent, OpenCode, and generic provider adapters |
| [UI.md](UI.md) | Desktop information architecture and interaction states |
| [XERJ.md](XERJ.md) | Search, indexing, and memory integration |
| [SECURITY.md](SECURITY.md) | Threat model, permissions, and local security defaults |
| [TESTING.md](TESTING.md) | Test layers and concurrency scenarios |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Bootstrap and local development conventions |
| [OPERATIONS.md](OPERATIONS.md) | SQLite backup, migration rollback, crash recovery |
| [RELEASE.md](RELEASE.md) | Security, accessibility, and macOS signing checklist |
| [DECISIONS.md](DECISIONS.md) | Initial architectural decisions and open questions |
| [SOURCES.md](SOURCES.md) | Primary technical references |

How to run, what is left, and the short leftover list live in the root [`README.md`](../README.md). How to use the app: [`USER.md`](USER.md). Agent rules live in [`/AGENTS.md`](../AGENTS.md).

## Non-goals for the first release

- Building a new foundation model or model gateway.
- Replacing Git, provider authentication, or provider billing.
- Silently auto-merging unreviewed agent changes.
- Treating natural-language messages as enforceable locks.
- Storing canonical coordination state only in Markdown or search indices.
- Exposing any local control endpoint beyond loopback.
- Exposing a public A2A gateway or remote-agent discovery by default.
