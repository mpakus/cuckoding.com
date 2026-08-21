# Architecture Decisions

This file contains compact initial decisions. Promote a decision into a dedicated `docs/adr/NNNN-title.md` when it needs alternatives, consequences, or revision history beyond a short entry.

## ADR-001 — ExTauri with Phoenix LiveView

Status: Accepted

Use ExTauri to package a Phoenix LiveView application as a native desktop app. Elixir/OTP remains the primary application and orchestration runtime; Tauri supplies the native shell and desktop APIs.

Reason: It matches the team's Elixir/Phoenix strengths and gives agent lifecycle/concurrency a natural OTP implementation while avoiding a separate React state layer.

## ADR-002 — Structured provider integrations

Status: Accepted

Use structured provider interfaces rather than terminal-screen parsing. Codex App Server is the primary Codex integration, with non-interactive JSONL as fallback. Claude uses its documented structured headless/streaming interface behind a separate adapter. Cursor Agent and OpenCode use ACP over stdio as their primary integrations, sharing a protocol client while retaining provider-specific adapters.

Reason: Structured events support reliable tabs, approvals, resume, telemetry, and testing.

## ADR-003 — SQLite is canonical

Status: Accepted

Use SQLite/Ecto for durable Agent Cards, A2A contexts, tasks, delegations, sessions, leases, messages, deliveries, idempotency records, worktrees, artifacts, and normalized events.

Reason: AgentDesk is local-first and single-machine. SQLite simplifies installation and backup while providing transactions required for coordination.

## ADR-004 — Git worktree per agent by default

Status: Accepted

Give every implementation agent its own linked Git worktree and branch. Shared checkout mode is experimental and opt-in.

Reason: Advisory file locks cannot prevent every provider or shell command from modifying a file. Worktrees preserve changes even when agents ignore messages.

## ADR-005 — Lease-based resource coordination

Status: Accepted

Use shared/exclusive leases with TTL, heartbeat, expiry, and explicit release. Do not use permanent `.lock` files as canonical state.

Reason: Provider processes and the desktop app can crash. Leases recover automatically and cover non-file resources.

## ADR-006 — MCP as the Agent Hub surface

Status: Accepted

Expose the built-in internal A2A and coordination operations to providers through a local authenticated MCP server.

Reason: Codex, Claude Code, Cursor Agent, and OpenCode support MCP, and it gives all providers the same structured tools without database access.

## ADR-007 — PubSub is ephemeral

Status: Accepted

Use Phoenix PubSub for immediate UI, A2A task subscription, and process notifications after state commits. Reload canonical state from SQLite after disconnect or restart.

Reason: PubSub is excellent for live fan-out but not a durable queue.

## ADR-008 — XERJ is an optional projection

Status: Accepted

Use XERJ for project search, semantic retrieval, long-term memory, and searchable historical summaries. Keep it behind `AgentDesk.Search.Adapter` and a feature flag.

Reason: XERJ directly addresses code/document retrieval and namespaced memory, but coordination must continue if it is missing or unhealthy.

## ADR-009 — Provider CLIs are initially user-installed

Status: Accepted for MVP

Discover supported provider CLIs on the user's machine instead of bundling them.

Reason: This preserves existing authentication and provider update flows and avoids early licensing/packaging complexity.

## ADR-010 — Custom structured UI before PTY

Status: Accepted for MVP

Build normalized LiveView activity, approval, diff, and prompt components. Defer generic PTY terminal emulation.

Reason: All four MVP providers expose structured automation protocols; a PTY adds complexity without improving the core multi-agent workflow.

## ADR-011 — Shared ACP transport, separate provider adapters

Status: Accepted for MVP

Implement one strict ACP client transport for Cursor Agent and OpenCode, then layer independent provider adapters above it.

Reason: Both providers use newline-delimited JSON-RPC over stdio, so framing, correlation, cancellation, and base session handling should not be duplicated. Their authentication, extensions, models, permissions, compatibility ranges, and fallback interfaces can differ and must remain isolated.

## ADR-012 — Internal A2A is a built-in core domain

Status: Accepted for MVP

Start a project-scoped internal A2A runtime with every project. Route provider agents through authenticated MCP tools into safe Agent Card discovery, transactional delegation, durable multipart messages, ordered per-recipient delivery, acknowledgements, task state, artifacts, handoffs, and resource coordination.

Reason: Multi-agent collaboration is the product's central behavior, not an optional integration. A durable provider-neutral domain lets agents cooperate even when a recipient is busy, a provider lacks active-turn steering, or the desktop app restarts.

The internal model follows A2A 1.0 concepts where useful but is not a public wire implementation. Resource leases and Git worktree authority remain AgentDesk extensions. Public A2A federation belongs behind a future adapter/gateway.

## ADR-013 — No direct peer transport

Status: Accepted for MVP

Provider processes do not open connections to one another. All discovery, delegation, messages, task updates, and artifacts pass through Agent Hub authorization and SQLite-backed routing.

Reason: Hub mediation supplies identity, auditability, ordering, idempotency, restart recovery, policy enforcement, and a consistent UI. Direct peer sockets would create provider-specific security and delivery behavior.

## ADR-014 — Phoenix 1.8 / OTP 28 scaffold

Status: Accepted for Phase 1

Generate the OTP application at the repository root as `AgentDesk` with Phoenix 1.8.1, LiveView, Bandit, and `ecto_sqlite3`. Develop on Elixir 1.19 / OTP 28; keep the Mix requirement at Elixir 1.15+ until ExTauri packaging is verified. Bind the HTTP endpoint to loopback. Persist application data under a configurable `data_root` rather than the opened Git repository.

Reason: The product repo already held the architecture docs; nesting a second `agent_desk/` app would split the working tree. Loopback binding matches `SECURITY.md`. OTP 28 is the local toolchain; ExTauri 0.2.0 warns that Burrito may lack a pre-compiled OTP 28 ERTS, so production packaging remains a Phase 0 check. `mix ex_tauri.install` generated `src-tauri/`; bundle icons are still placeholder paths.

## Open decisions

### MCP implementation library

Run a Phase 0 compatibility and maintenance spike before selecting a dependency or implementing the required subset directly.

### Claude long-term integration

Compare CLI streaming with the Claude Agent SDK for multi-turn control, stability, packaging, and session resume.

### OpenCode server fallback

Compare ACP with the loopback OpenAPI server only after the ACP spike. Adopt the server path only if it supplies a required stable capability without weakening local authentication or adding an unnecessary runtime.

### Public A2A gateway

After MVP, choose supported A2A 1.0 bindings, authentication, Agent Card exposure policy, and remote-agent trust model. The gateway must translate to the internal domain and remain disabled by default.

### XERJ distribution

Choose between bundled binary, managed download, or external discovery after measuring bundle size, platform support, update requirements, and release-candidate stability.

### Database isolation adapters

Define project templates for PostgreSQL database-per-agent, schema-per-agent, test partitions, and Docker Compose project isolation after the base worktree flow is working.

### Product name

`AgentDesk` is a working name only.
