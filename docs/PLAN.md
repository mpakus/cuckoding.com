# Implementation Plan

Phases 1–6 and post-MVP items through ADR-026 are implemented. Still open: wrap the Mix release in ExTauri/Burrito on OTP 28 (unchecked below), Apple signing/notarization, Linux/Windows installer smoke, and the public A2A gateway (deferred). Local unsigned packaging is `mix cuckoding.app`. See the root `README.md` leftover table.

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
- [ ] Confirm production ExTauri/Burrito packaging on Apple Silicon (`MIX_ENV=prod mix release desktop` works on OTP 28; `mix cuckoding.app` copies that release into the Tauri `.app`; `mix ex_tauri.build` still has no OTP 28 Burrito ERTS — ADR-014/ADR-015).
- [x] Confirm graceful shutdown of BEAM and child processes.
- [x] Start `codex app-server` over stdio and complete initialize, thread, turn, stream, approval, interrupt, and resume flows (fixture-backed adapter; live CLI optional).
- [x] Start Claude Code in structured headless/streaming mode and complete start, stream, interrupt, and resume flows where supported.
- [x] Start Cursor CLI with `agent acp`; exercise initialize, authenticate, new/load session, stream, permission, cancel, and resume flows, recording any version-gated capability.
- [x] Start OpenCode with `opencode acp --cwd <worktree>`; exercise initialize, new/load session, stream, permission, cancel, and resume flows, recording unsupported or version-gated capabilities explicitly.
- [x] Compare the shared ACP client core against provider-specific Cursor and OpenCode extensions and record the supported protocol versions.
- [x] Verify how per-session MCP configuration is injected into each provider without modifying global user configuration.
- [x] Prototype an MCP tool implemented by the Phoenix/Elixir application.
- [x] Run two fake providers through discovery, delegation, accept/reject, structured message, acknowledgement, artifact publication, and restart recovery.
- [x] Validate the internal task/message/artifact mapping against A2A 1.0 while keeping the internal transport private and MCP-backed.
- [x] Create and remove an app-owned Git worktree safely.
- [x] Start XERJ locally, autoindex a sample repository, search it, store memory, and terminate it cleanly.
- [x] Measure memory and startup cost with four simultaneous sessions, including one Cursor and one OpenCode session (fake/ACP fixtures; live Cursor+OpenCode load remains Phase 6).

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

- [x] Implement per-session capabilities and Agent Hub authentication.
- [x] Implement MCP initialization, tool discovery, and tool calls.
- [x] Start the internal A2A supervisor automatically for every project runtime.
- [x] Add Agent Card registration, revisioning, heartbeat, availability, and capability-safe peer discovery.
- [x] Add task contexts and transactional delegation with propose, accept, reject, expire, revoke, and redirect flows.
- [x] Add direct, task-scoped, context-scoped, and project broadcast messages.
- [x] Support bounded text, structured data, artifact references, and approved file references as message parts.
- [x] Add inbox cursors and delivery acknowledgements.
- [x] Add per-session idempotency for every mutating A2A tool.
- [x] Add task update subscriptions through PubSub-backed internal routing and durable reload.
- [x] Add artifact publication, retrieval, integrity validation, and task association.
- [x] Implement exact-file and named-resource leases.
- [x] Implement renewal, release, expiry, and conflict reporting.
- [x] Add Agents directory, capability cards, delegation inbox, task conversation, artifact, resource, and message panels to the UI.
- [x] Add generated human-readable status snapshots.
- [x] Queue cross-agent notices and inject them only at safe provider boundaries.
- [x] Enforce autonomous delegation depth, fan-out, rate, size, and permission policy.

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

- [x] Implement repository validation and default-branch detection.
- [x] Add one branch/worktree per agent session.
- [x] Record base/head commits and dirty state.
- [x] Add diff, commit, and handoff UI.
- [x] Add review requests between agents.
- [x] Link handoffs and reviews to A2A contexts, messages, delegations, and immutable artifacts.
- [x] Implement safe cherry-pick/merge preparation without silent conflict resolution.
- [x] Detect main-tree and worktree changes through the project watcher.
- [x] Add unexpected-edit warnings.
- [x] Implement per-agent port allocation.
- [x] Define adapters for isolated test database/schema and Docker Compose project names.
- [x] Write PostgreSQL/schema/partition/Compose templates into the app-owned session directory.
- [x] Add explicit cleanup and stale-worktree reconciliation.

Acceptance criteria:

- Concurrent agents can change the same logical repository without overwriting filesystem changes.
- Handoff includes commit, summary, changed files, validation, and warnings.
- Conflicts are visible and never cause automatic data loss.
- App restart preserves every dirty worktree.

## Phase 5 — XERJ search and memory

- [x] Implement `AgentDesk.Search.Adapter`.
- [x] Add XERJ binary discovery, startup, health check, and shutdown.
- [x] Store XERJ data in the application-data directory.
- [x] Autoindex project content after project open.
- [x] Debounce re-indexing after file changes.
- [x] Add shared, per-agent, and per-task memory namespaces.
- [x] Add MCP tools for search, remember, recall, and forget.
- [x] Index decisions, handoffs, artifacts, and selected event summaries.
- [x] Add search readiness and rebuild controls to the UI.
- [x] Verify that deleting XERJ data and rebuilding preserves canonical behavior.

Acceptance criteria:

- Search failure never blocks provider sessions, leases, or Git operations.
- Agents receive bounded, source-attributed search results.
- Namespace authorization prevents one project from reading another project's memory.
- The complete search index can be rebuilt from canonical data.

## Phase 6 — Hardening and distribution

- [x] Add startup reconciliation for sessions, leases, worktrees, ports, and child processes.
- [x] Add crash-loop backoff and circuit breakers for providers and XERJ.
- [x] Add secret redaction and diagnostic export review.
- [x] Add capability/token rotation and expiry.
- [x] Add permission profiles per provider and project.
- [x] Add database backup and migration rollback guidance.
- [x] Document macOS signing, notarization, and updater pipeline (execution waits on Apple certificates and OTP 28 packaging).
- [x] Add accessibility and keyboard navigation review.
- [x] Load-test long transcripts and four concurrent agents.
- [x] Load-test A2A broadcast fan-out, inbox recovery, delegation races, and task subscriptions with four concurrent agents.
- [x] Complete security review and release checklist.

Acceptance criteria:

- Forced application termination does not lose agent worktrees or corrupt SQLite.
- No control endpoint is reachable beyond loopback.
- Diagnostic exports contain no known credential patterns in test fixtures.
- Signed/notarized builds install and upgrade successfully on a clean Mac (deferred until certificates and OTP 28 packaging land; checklist is in `docs/RELEASE.md`).

## Post-MVP roadmap

- [x] Linux and Windows packaging notes (OTP 28 Burrito/ExTauri still unverified; see `docs/RELEASE.md`).
- [x] Multiple simultaneously open projects.
- [x] Directory and glob leases with visual overlap previews.
- [x] Review/merge queues and policy gates.
- [x] Provider SDK adapters and remote agents.
- [x] Task dependency graphs and reusable workflows.
- [x] User-defined agent roles and prompt templates.
- [x] Cost/token dashboards.
- [x] Optional containerized execution.
- [x] Team synchronization across machines (user-initiated redacted bundles; not a network service).
- Authenticated public A2A 1.0 gateway for selected remote agents.

## Explicitly deferred decisions

- Product name is Cuckoding (ADR-025). OTP modules stay `AgentDesk` / `AgentDeskWeb`. Dark-only UI is shipped; there is no theme switch.
- Whether XERJ is bundled or downloaded on demand.
- The Elixir MCP implementation dependency.
- Whether a future public A2A gateway is implemented directly in Elixir or through a separately maintained protocol adapter; the internal A2A domain is unaffected.
- Whether Claude integration uses CLI streaming or its Agent SDK as the long-term primary path.
- A generic PTY terminal mode; it is not needed for the custom structured UI.
