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

Reason: The product repo already held the architecture docs; nesting a second `agent_desk/` app would split the working tree. Loopback binding matches `SECURITY.md`. OTP 28 is the local toolchain; ExTauri 0.2.0 warns that Burrito may lack a pre-compiled OTP 28 ERTS, so production Burrito wrapping remains open. Local packaging is `mix cuckoding.app` (Mix release copied into the Tauri `.app`). Bundle identifiers live in `src-tauri/tauri.conf.json` (`com.agentdesk.app`, product name Cuckoding).

## ADR-015 — Phase 0 spike results

Status: Accepted for Phase 0

Recorded from the Phoenix/ExTauri application at the repository root, fixture-backed provider adapters, the built-in MCP Agent Hub, Git worktrees, and optional XERJ.

- **Hot reload / packaging (Apple Silicon):** `mix phx.server` and `mix ex_tauri.dev` are the development path. Phoenix `CodeReloader` is enabled. `MIX_ENV=prod mix release desktop` assembles `_build/prod/rel/desktop` on OTP 28. `mix cuckoding.app` copies that Mix release into `Cuckoding.app` because Burrito does not emit an OTP 28 ERTS for ExTauri 0.2.0 to wrap. `mix ex_tauri.build` without that sidecar still fails wrapping. Quit the running `.app` / leftover `beam.smp` before rebuild.
- **Graceful shutdown:** `ExTauri.ShutdownManager` is the first supervisor child. Project runtimes trap exits and stop A2A, worktree, and search supervisors. Provider `SessionWorker` closes the OS `Port` on terminate and records `process_identity.os_pid`.
- **Codex App Server:** Adapter talks JSON-RPC stdio (`initialize`, session, prompt, interrupt, approvals, resume). Primary path is structured JSONL, not ANSI. Live CLI coverage skips when `codex` is missing and never sends a paid prompt; CI stays fixture-backed. `codex exec --json` remains the one-shot fallback.
- **Claude Code:** Structured headless/streaming adapter. Resume is declared only where the adapter implements it. Unsupported encode actions return `{:error, :unsupported_action}` instead of scraping a TTY.
- **Cursor ACP:** `agent acp` through `AgentDesk.Providers.ACP.Client`. Shared framing; Cursor owns extensions. `steer_active_turn` is false.
- **OpenCode ACP:** `opencode acp --cwd <worktree>` through the same ACP client. The loopback OpenAPI server is not an MVP runtime dependency.
- **ACP vs extensions:** One JSON-RPC transport; Cursor and OpenCode adapters remain separate (ADR-011). Protocol version is negotiated at initialize; unknown methods are rejected, not guessed.
- **Per-session MCP injection:** `AgentDesk.Providers.MCPInjection` writes `mcp.json` under the session directory in application-data. It never edits global provider config.
- **MCP prototype:** `AgentDesk.MCP.Protocol` implements JSON-RPC `initialize`, `tools/list`, and `tools/call` for hub, lease, handoff, and search tools.
- **Two fake providers:** Fixture ACP peers cover discovery, delegation, accept/reject, structured messages, ack, artifacts, and restart recovery in A2A tests.
- **A2A mapping:** Internal domain follows A2A 1.0 concepts; transport is private MCP. Public A2A wire types are not leaked.
- **Git worktrees:** App-owned worktrees under `Storage.worktree_dir/2`, branch `agentdesk/<session_id>`, cleanup only when app-owned, path-matched, linked, and not dirty.
- **XERJ:** Optional. Binary discovery, `--insecure --bind 127.0.0.1 --data-dir <Storage.xerj_dir>`, health against loopback `:9200`, autoindex, `/_memory` namespaces, and clean Port shutdown. AgentDesk never attaches to a XERJ node it did not start (occupied `:9200` is treated as unavailable). When the binary is missing the `Search.Adapter` returns `unavailable` and coordination continues. CI uses the SQLite projection adapter, which is rebuildable from canonical files and SQLite. Live spike against `xerj v1.0.0-rc.14`: node start and HTTP health work; autoindex/search/memory must use an AgentDesk-owned data dir, not a pre-existing node.
- **Four-session cost:** Four concurrent fake sessions start under `ProviderProcessSupervisor` and persist OS pids. Unbounded-growth load testing remains Phase 6.

Unsupported or deferred capabilities (explicit):

- Generic PTY / ANSI terminal parsing (ADR-010).
- OpenCode HTTP server fallback.
- Claude Agent SDK as a second Claude transport.
- Production ExTauri/Burrito packaging on OTP 28 (`mix release desktop` and `mix cuckoding.app` work; Burrito ERTS wrap still missing).
- Bundled XERJ binary (external discovery for MVP).
- Cursor/OpenCode `steer_active_turn`.
- Hosted embeddings (opt-in later; default is local lexical).

No adapter's primary path parses ANSI screens. Child processes are identified by Port + `os_pid` and terminated through `Port.close/1`.

## ADR-016 — Phase 6 hardening defaults

Status: Accepted for Phase 6

Startup reconciliation expires leases, delegations, and capability tokens and interrupts orphan sessions. It never signals an OS pid from stored `process_identity` (PID reuse). Crash loops trip `AgentDesk.Circuit` after five failures. Diagnostic export is redacted. Permission profiles `default` and `observer`/`restricted` filter MCP tools. SQLite snapshots are copy-based; applied migrations are never edited in place. Signed macOS distribution waits on certificates and OTP 28 packaging.

## ADR-017 — Multiple live projects and glob leases

Status: Accepted

Keep one `ProjectRuntime` per open project under `Projects.Supervisor`. `projects.open` is canonical: opening sets it true without stopping other runtimes; closing sets it false and stops only that runtime. Boot restores every open project, not only `last_opened_at`.

Resource overlap treats `file`, `directory`, and `glob` as path-shaped. Glob matching is prefix + `*` / `**` pattern comparison in `Resources.Overlap`; it is never proof of ownership. The workspace lists colliding keys as a preview only.

Reason: The architecture already isolated runtimes per project. Restoring only the last project dropped concurrent sessions on restart. Directory overlap existed; glob claims and a visible collision list were the remaining ResourceManager gap.

## ADR-018 — Review/merge queue is explicit

Status: Accepted

Handoffs enqueue a `merge_queue_items` row. `hub_accept_handoff` persists `accepted` and never runs Git. Merge is a confirmed user action that requires `accepted`, `policy_status=passed`, a clean primary checkout on `target_ref`, and a conflict-free `merge-tree`. Failed or missing `project.settings["required_checks"]` block merge. Isolated agent worktrees are not modified by merge; only the user's primary checkout is, and only after that confirmation.

Reason: UI.md disables integration while checks fail or conflicts exist. AGENTS.md forbids auto-merge with failing required checks. MCP agents must not integrate into the primary tree.

## ADR-019 — Task graphs and reusable workflows

Status: Accepted

`parent_task_id` remains a nesting hint. Wait-edges live in `task_dependencies` and are cycle-checked in `A2A.Graph`. Incomplete prerequisites set `blocked`; completing a prerequisite unblocks dependents that have no remaining unfinished edges. Failed or cancelled prerequisites do not unblock. Reusable workflows are project-scoped templates; instantiating them creates tasks and edges. MCP `hub_run_workflow` and the LiveView step list both go through that path.

Reason: UI.md asks for optional dependencies and current-task dependency visibility. A DAG is the missing coordination primitive after single-parent tasks.

## ADR-020 — User-defined roles stay off Agent Cards

Status: Accepted

Project-scoped `agent_roles` rows hold a name, safe description, permission profile, and a prompt template. Starting a session copies the role name and `permission_profile` onto the session. The prompt is interpolated with `{{display_name}}` and `{{role}}` and injected only into that provider session after handshake. Agent Cards, MCP `hub_list_roles`, and diagnostic events expose name/description/profile only. Roles cannot be named after credential keys. MCP cannot save or rewrite prompts.

Reason: PROVIDERS.md derives Agent Cards from user role settings plus verified capabilities. Hidden prompts and credentials must never appear on cards or peer-visible discovery.

## ADR-021 — SDK JSONL and loopback attach

Status: Accepted

`sdk` is a structured JSONL adapter for a user-supplied executable plus argument array. Commands use `op`; events use `type` and `Event.type_from_string/1`. Relative paths with directories are rejected. `remote` sessions do not spawn a child: AgentDesk issues a capability token, writes `mcp.json` and `connect.env` (mode 0600) under the session directory, and delivers UI prompts through the durable A2A inbox. Agents connect inbound over loopback MCP. This is not a public A2A 1.0 gateway.

Reason: PLAN calls for provider SDK adapters and remote agents. DECISIONS keeps the public gateway deferred. Attach is the local-first equivalent: bring-your-own process, same hub, no LAN bind.

## ADR-022 — Usage samples are canonical

Status: Accepted

Normalized `:usage` events persist to `usage_samples` with integer token counts and optional integer `cost_cents`. The workspace usage panel reads SQLite totals. Usage is never sourced from XERJ or PubSub.

Reason: PROVIDERS.md requires usage events on the capability model. Cost/token dashboards need a rebuildable ledger; floats are forbidden for money.

## ADR-023 — Optional Compose stays off the primary tree

Status: Accepted

Containerized execution is opt-in per session (`settings["container"]`). AgentDesk runs `docker compose` as an executable plus argument array with a unique `-p` project name from `Isolation.compose_project/1`. It only uses the session worktree, never the user's primary checkout or shared-workspace mode. Compose files that mention `0.0.0.0`, `network_mode: host`, or `privileged:` are rejected. Published services should bind `127.0.0.1` via `AGENTDESK_BIND`. Stacks are claimed as exclusive `service` leases and torn down on session terminate and startup reconcile. Docker is not required when the option is off; CI uses a fixture CLI.

Reason: PLAN calls for optional containerized execution. AGENTS.md already required per-agent Compose project names and forbids isolated-mode edits to the primary worktree. Loopback binding matches SECURITY.md.

## ADR-024 — Team sync is a file bundle

Status: Accepted

Team synchronization is a user-initiated export/import of a redacted JSON bundle (`agentdesk.sync.v1`). Bundles carry tasks, wait-edges, workflows, and role templates. They do not carry capability tokens, leases, live sessions, worktrees, search indexes, or provider secrets. Import is allowed when `project.settings["sync_id"]` matches or when canonical Git `origin` URLs match. AgentDesk does not open a sync listener, does not bind beyond loopback, and does not implement a public A2A gateway.

Reason: PLAN calls for team synchronization across machines. Local-first architecture keeps Git as the code transport and SQLite as canonical coordination state. A hosted sync service or public A2A wire would contradict DECISIONS.md until the gateway ADR is accepted.

## ADR-025 — Product name is Cuckoding

Status: Accepted

The user-facing product name is **Cuckoding**. OTP application modules remain `AgentDesk` / `AgentDeskWeb` and Mix app `:agent_desk` so existing data paths, registries, and docs links stay stable. Application Support still uses `AgentDesk` unless a later migration moves `data_root`.

Reason: The repo and brand are Cuckoding; renaming BEAM modules would churn every module, test, and SQLite backup without changing behavior.

## ADR-026 — Isolation templates stay off the primary tree

Status: Accepted

`AgentDesk.Isolation` still owns unique database, schema, ExUnit partition, Compose project, and port names. Starting a session writes copy-paste templates into the app-owned session directory and injects the same values into the provider environment (`AGENTDESK_TEST_DATABASE`, `AGENTDESK_TEST_SCHEMA`, `AGENTDESK_TEST_PARTITION` / `MIX_TEST_PARTITION`, `AGENTDESK_COMPOSE_PROJECT`, `AGENTDESK_BIND`, optional `AGENTDESK_PORT`). MCP `hub_isolation` returns that profile. Isolated sessions do not write these files into the Git worktree or the user's primary checkout.

Reason: README leftover and the open database-isolation decision asked for templates after worktrees existed. AGENTS.md forbids isolated-mode edits to the primary tree. Compose already used Isolation names; tests and Postgres needed the same contract.

## ADR-027 — Lead crew split is durable A2A work

Status: Accepted

A user or lead agent can split a goal into specialist lanes (backend, frontend, tests by default). The hub creates a parent task, child tasks, a review task with wait-edges, and shared SQLite memory. Delegations are recorded. For a user-started crew, or when the lead assigns those launched specialists, the hub accepts immediately so work can start. Ad-hoc `hub_delegate_task` remains a proposal until accept. Completing a lane notifies the lead through the durable inbox and a best-effort provider prompt. Agents still cannot query SQLite or open peer sockets. This does not auto-merge to the primary tree.

Reason: Concurrent specialists need a lead that can analyze, split, and review. Tasks, messages, and memory already existed; the missing piece was the analyze → split → review loop.

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
