# Implementation Plan

## Guiding constraints

- macOS-first, while keeping platform abstractions explicit.
- Local-first and functional without a cloud AgentDesk account.
- Provider-neutral domain model.
- Git worktree isolation by default.
- SQLite is canonical; XERJ is optional and rebuildable.
- Structured provider protocols take priority over terminal scraping.
- Internal A2A coordination is built in, provider-neutral, durable, and hub-mediated.
- Least-privilege execution and explicit approvals.

## MVP exit criteria

The MVP is complete when a user can open a Git project, launch Codex, Claude Code, Cursor Agent, and OpenCode in separate tabs, let agents discover one another's safe capabilities, delegate and accept/reject tasks, exchange acknowledged structured messages, publish artifacts, claim resources, produce isolated commits, review handoffs, restart the desktop app without losing A2A state, and safely clean up app-owned worktrees.

## Phase 0 — Technical spikes

Goal: prove every high-risk integration before building the product shell.

- [x] Scaffold a minimal Phoenix LiveView application with ExTauri.
- [ ] Confirm development hot reload and production packaging on Apple Silicon.
- [ ] Confirm graceful shutdown of BEAM and child processes.
- [ ] Start `codex app-server` over stdio and complete initialize, thread, turn, stream, approval, interrupt, and resume flows.
- [ ] Start Claude Code in structured headless/streaming mode and complete start, stream, interrupt, and resume flows where supported.
- [ ] Start Cursor CLI with `agent acp`; exercise initialize, authenticate, new/load session, stream, permission, cancel, and resume flows, recording any version-gated capability.
- [ ] Start OpenCode with `opencode acp --cwd <worktree>`; exercise initialize, new/load session, stream, permission, cancel, and resume flows, recording unsupported or version-gated capabilities explicitly.
- [ ] Compare the shared ACP client core against provider-specific Cursor and OpenCode extensions and record the supported protocol versions.
- [ ] Verify how per-session MCP configuration is injected into each provider without modifying global user configuration.
- [ ] Prototype an MCP tool implemented by the Phoenix/Elixir application.
- [ ] Run two fake providers through discovery, delegation, accept/reject, structured message, acknowledgement, artifact publication, and restart recovery.
- [ ] Validate the internal task/message/artifact mapping against A2A 1.0 while keeping the internal transport private and MCP-backed.
- [ ] Create and remove an app-owned Git worktree safely.
- [ ] Start XERJ locally, autoindex a sample repository, search it, store memory, and terminate it cleanly.
- [ ] Measure memory and startup cost with four simultaneous sessions, including one Cursor and one OpenCode session.

Acceptance criteria:

- All spike results are recorded in `DECISIONS.md` or a new ADR.
- No adapter requires parsing ANSI terminal screens for its primary path.
- The app can identify and terminate every child process it starts.
- Unsupported provider capabilities are documented explicitly.

## Phase 1 — Application foundation

- [x] Generate the Phoenix application with LiveView and SQLite/Ecto.
- [x] Install and configure ExTauri.
- [x] Add formatter, Credo, Dialyxir, Sobelow, and ExCoveralls.
- [x] Establish project namespaces and supervision tree.
- [x] Add UUID-backed schemas and initial migrations from `DB.md` (projects and events; remaining tables follow with their phases).
- [x] Implement project open/close and recent-project persistence.
- [x] Add `ProjectRuntime` under `DynamicSupervisor`.
- [x] Add common event envelope and append-only event writer.
- [x] Add common `context_id`, `correlation_id`, `causation_id`, `idempotency_key`, and optimistic-version conventions.
- [x] Add migrations for Agent Cards, delegations, durable message delivery, and artifact references.
- [x] Add telemetry and structured local logging.
- [x] Create the initial application shell and navigation.

Acceptance criteria:

- The packaged app opens a repository and restores it after restart.
- Project runtimes start and stop independently.
- Database migrations run automatically with recoverable errors.
- CI passes formatting, compilation, unit tests, Credo, Dialyzer, and Sobelow.

## Phase 2 — Provider sessions and tabs

- [x] Define the provider adapter behavior and normalized event types.
- [x] Implement provider discovery/version probing.
- [x] Implement Codex App Server adapter.
- [x] Implement Codex one-shot adapter fallback.
- [x] Implement Claude Code structured adapter.
- [x] Implement a reusable ACP client transport with strict JSON-RPC framing and capability negotiation.
- [x] Implement Cursor ACP adapter and Cursor extension-event normalization.
- [x] Implement OpenCode ACP adapter, with its local server API retained as an evaluated fallback rather than an MVP dependency.
- [x] Persist provider session/thread identifiers.
- [x] Auto-inject the Agent Hub MCP surface and register an internal Agent Card for every first-class provider session.
- [x] Implement safe-boundary delivery from the durable A2A inbox into each provider adapter.
- [x] Implement start, input, stream, pause/wait, interrupt, resume, and terminate flows.
- [x] Surface approval requests in LiveView.
- [x] Add transcript persistence with redaction.
- [x] Build tabs, activity stream, prompt composer, and status indicators.
- [x] Add bounded buffering/backpressure for high-volume provider output.

Acceptance criteria:

- Sessions from any two supported providers can run concurrently without UI blocking, and all four provider adapters pass the same lifecycle contract suite.
- Closing a tab does not silently kill an active session.
- Provider crash produces a recoverable failed state.
- Session history survives application restart when the provider supports resume.

## Phase 3 — Built-in internal A2A Hub and coordination

- [ ] Implement per-session capabilities and Agent Hub authentication.
- [ ] Implement MCP initialization, tool discovery, and tool calls.
- [ ] Start the internal A2A supervisor automatically for every project runtime.
- [ ] Add Agent Card registration, revisioning, heartbeat, availability, and capability-safe peer discovery.
- [ ] Add task contexts and transactional delegation with propose, accept, reject, expire, revoke, and redirect flows.
- [ ] Add direct, task-scoped, context-scoped, and project broadcast messages.
- [ ] Support bounded text, structured data, artifact references, and approved file references as message parts.
- [ ] Add inbox cursors and delivery acknowledgements.
- [ ] Add per-session idempotency for every mutating A2A tool.
- [ ] Add task update subscriptions through PubSub-backed internal routing and durable reload.
- [ ] Add artifact publication, retrieval, integrity validation, and task association.
- [ ] Implement exact-file and named-resource leases.
- [ ] Implement renewal, release, expiry, and conflict reporting.
- [ ] Add Agents directory, capability cards, delegation inbox, task conversation, artifact, resource, and message panels to the UI.
- [ ] Add generated human-readable status snapshots.
- [ ] Queue cross-agent notices and inject them only at safe provider boundaries.
- [ ] Enforce autonomous delegation depth, fan-out, rate, size, and permission policy.

Acceptance criteria:

- Every supported provider automatically receives the same internal A2A MCP surface.
- An agent can discover an eligible peer without seeing credentials or private prompts.
- A delegation decision and task assignment commit atomically and survive restart.
- Structured messages are ordered per recipient, idempotent, durable, and acknowledged.
- Task results are published as integrity-checked artifacts rather than only chat messages.
- An agent can announce a task, claim files, broadcast progress, and release resources through MCP.
- A conflicting exclusive claim is rejected deterministically.
- Killing an agent causes its leases to expire within the configured grace period.
- Restart recovery cannot resurrect an expired lease.

## Phase 4 — Git worktrees and resource isolation

- [ ] Implement repository validation and default-branch detection.
- [ ] Add one branch/worktree per agent session.
- [ ] Record base/head commits and dirty state.
- [ ] Add diff, commit, and handoff UI.
- [ ] Add review requests between agents.
- [ ] Link handoffs and reviews to A2A contexts, messages, delegations, and immutable artifacts.
- [ ] Implement safe cherry-pick/merge preparation without silent conflict resolution.
- [ ] Detect main-tree and worktree changes through the project watcher.
- [ ] Add unexpected-edit warnings.
- [ ] Implement per-agent port allocation.
- [ ] Define adapters for isolated test database/schema and Docker Compose project names.
- [ ] Add explicit cleanup and stale-worktree reconciliation.

Acceptance criteria:

- Concurrent agents can change the same logical repository without overwriting filesystem changes.
- Handoff includes commit, summary, changed files, validation, and warnings.
- Conflicts are visible and never cause automatic data loss.
- App restart preserves every dirty worktree.

## Phase 5 — XERJ search and memory

- [ ] Implement `AgentDesk.Search.Adapter`.
- [ ] Add XERJ binary discovery, startup, health check, and shutdown.
- [ ] Store XERJ data in the application-data directory.
- [ ] Autoindex project content after project open.
- [ ] Debounce re-indexing after file changes.
- [ ] Add shared, per-agent, and per-task memory namespaces.
- [ ] Add MCP tools for search, remember, recall, and forget.
- [ ] Index decisions, handoffs, artifacts, and selected event summaries.
- [ ] Add search readiness and rebuild controls to the UI.
- [ ] Verify that deleting XERJ data and rebuilding preserves canonical behavior.

Acceptance criteria:

- Search failure never blocks provider sessions, leases, or Git operations.
- Agents receive bounded, source-attributed search results.
- Namespace authorization prevents one project from reading another project's memory.
- The complete search index can be rebuilt from canonical data.

## Phase 6 — Hardening and distribution

- [ ] Add startup reconciliation for sessions, leases, worktrees, ports, and child processes.
- [ ] Add crash-loop backoff and circuit breakers for providers and XERJ.
- [ ] Add secret redaction and diagnostic export review.
- [ ] Add capability/token rotation and expiry.
- [ ] Add permission profiles per provider and project.
- [ ] Add database backup and migration rollback guidance.
- [ ] Add macOS signing, notarization, and updater pipeline.
- [ ] Add accessibility and keyboard navigation review.
- [ ] Load-test long transcripts and four concurrent agents.
- [ ] Load-test A2A broadcast fan-out, inbox recovery, delegation races, and task subscriptions with four concurrent agents.
- [ ] Complete security review and release checklist.

Acceptance criteria:

- Forced application termination does not lose agent worktrees or corrupt SQLite.
- No control endpoint is reachable beyond loopback.
- Diagnostic exports contain no known credential patterns in test fixtures.
- Signed/notarized builds install and upgrade successfully on a clean Mac.

## Post-MVP roadmap

- Linux and Windows packaging.
- Multiple simultaneously open projects.
- Directory and glob leases with visual overlap previews.
- Review/merge queues and policy gates.
- Provider SDK adapters and remote agents.
- Task dependency graphs and reusable workflows.
- User-defined agent roles and prompt templates.
- Cost/token dashboards.
- Optional containerized execution.
- Team synchronization across machines.
- Authenticated public A2A 1.0 gateway for selected remote agents.

## Explicitly deferred decisions

- Final product name and visual identity.
- Whether XERJ is bundled or downloaded on demand.
- The Elixir MCP implementation dependency.
- Whether a future public A2A gateway is implemented directly in Elixir or through a separately maintained protocol adapter; the internal A2A domain is unaffected.
- Whether Claude integration uses CLI streaming or its Agent SDK as the long-term primary path.
- A generic PTY terminal mode; it is not needed for the custom structured UI MVP.
