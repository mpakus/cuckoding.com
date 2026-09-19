# Product Specification

## Vision

Cuckoding is a visual, local-first operating system for coding-agent work on a developer's Mac. It begins with the developer's existing projects, reusable agent connections, and role definitions; boards then turn tasks into durable multi-stage processes. Cuckoding keeps that work alive for hours or days and exposes project state, active roles, evidence, cost, resource load, accumulated knowledge, and controls in one browser dashboard reachable from a menubar icon.

It is not a chat client and it is not an autonomous merge bot. Its product value is coordination, durability, evidence, and compounding project knowledge.

## Target users

- Individual developers using two or more coding agents who want to run several features in parallel without babysitting terminals.
- Small teams that need repeatable agent workflows without moving private repositories to a hosted control plane.
- Engineering leads comparing model/runtime performance and cost across real tasks.
- Security-sensitive teams that require local execution and inspectable audit trails.

## Core jobs to be done

1. Open the application and immediately see registered projects, application health, current resource use, attention items, and who is working on what.
2. Add a project through a short guided setup for its name, native-selected folder, and Git base branch, then manage reusable agent connections and default role assignments on the project page. The folder may be empty, an unborn Git repository, or an existing project.
3. Create several independent boards for a project, such as product features, maintenance, and security remediation.
4. Choose or customize a workflow and map its roles to the project's connected agents.
5. Add tasks manually or ask one assigned agent to inspect project documentation and propose tasks; review the proposals before importing them as Draft cards.
6. Let approved tasks progress through gates for as long as they need, including across laptop sleep.
7. Watch on the global dashboard and Agent Floor which role and runtime is doing what, without exposing private reasoning.
8. Open each run's worktree and local preview URL.
9. Pause, hibernate, retry, or stop work without losing durable state.
10. Inspect changes, test results, review findings, cost, tokens, cache behavior, CPU, and memory.
11. Produce a branch and optional draft pull request for human review.
12. Compress completed work into reviewed project knowledge and skills, see the knowledge base grow, and see where it was used and whether it helped.
13. Plug in tools already installed on the machine (XERJ, RTK, Ponytail, MCP servers, container runtimes) through connectors.

## MVP capabilities

- Local project registry with separate add/edit setup; creating a project does not create a board, task, run, branch, or worktree.
- A machine-wide saved-agent catalog plus project role defaults. The built-in roles are Specifications, Coding, and Review; users may attach the same saved agent to several projects, add roles, and edit role names/instructions. Output contracts belong to workflow/adapter configuration. The catalog stores connection metadata and authorization status, never credential values.
- Multiple boards and concurrent task flows per project.
- Read-only board planning runs that turn a bounded prompt into source-cited task proposals; only human-selected proposals become Draft tasks.
- Configurable stage templates and role-to-runtime assignment.
- Claude Code, Codex, and Cursor Agent as supported launch adapters. Cursor requires a fresh login in each run-owned home and refuses project Cursor MCP, sandbox, CLI, or plugin overrides. Project setup may also save OpenCode and Custom Agent connections, but task execution remains blocked until a reviewed adapter passes the conformance suite.
- Git worktree per run, host process runner with process-group supervision, path and command policy, per-run port allocation and preview URL.
- Durable state machine, retries, approvals, pause, hibernate, resume, crash recovery, and sleep/wake reconciliation.
- Power assertions while runs are active; unattended mode for long runs.
- Menubar shell with Cuckoding, About, Settings, Quit; UI in the default browser.
- Global operations dashboard (Agent Floor), per-board Kanban, run detail.
- Normalized activity stream, artifacts, diffs, test reports, and review findings.
- Token, cost, CPU, memory, duration, and cache telemetry with source/confidence labels.
- Knowledge store: per-run extraction, project consolidation, review queue, global publication, skill packaging, injection into runtimes, usage tracking, and dashboard views.
- Plugin registry with detection, health, and per-scope enablement; reference plugins for XERJ, RTK, Ponytail, and generic MCP servers.
- Draft pull request creation or an equivalent ready-to-push branch, executed host-side after approval.

## Explicit non-goals for MVP

- Container or VM isolation (container runners are a post-MVP plugin family).
- Fully autonomous production deployment or merging.
- Hosted multi-tenant execution.
- A general-purpose IDE or terminal replacement.
- Training or fine-tuning foundation models.
- Perfect cost comparison across providers that expose incompatible usage data.
- Mobile clients, Windows distribution, or x86 macOS distribution. Linux is a candidate second target because it needs no shell beyond a tray icon.

The complete launch contract, competitive basis, retention defaults, and commercial hypotheses are recorded in `docs/MVP_BOUNDARY_AND_POSITIONING.md`.

## Product principles

- Local-first, not local-only forever.
- Evidence before autonomy.
- Durable workflows, ephemeral workers.
- Provider-neutral product logic.
- Human approval at irreversible or cross-boundary actions.
- Honest metrics and honest isolation claims: measured, provider-reported, and estimated values remain distinct; the host runner is never called a sandbox.
- Graceful degradation when optional plugins are absent.
- Reusable knowledge must carry evidence, provenance, scope, validity, usage history, and a revocation path.

## Primary user journey

1. The user clicks the menubar icon → Cuckoding; the global dashboard opens with registered projects, health, resources, active work, and attention items.
2. The user chooses **Add project** or edits an existing project.
3. A three-step wizard collects project identity and a system-selected project folder plus Git base branch, then reviews the pending registration. Before confirmation it only inspects the folder. After explicit review, it initializes Git and creates the first local commit when no branch revision exists; an existing repository with the selected branch is not changed.
4. Confirming the wizard registers only the project and redirects to its settings page. There the user can add or reuse multiple saved agents, configure provider-specific authorization, edit or add roles, and assign one connection to each role. Every project save creates an immutable trusted configuration revision; it does not create or start work. One-time authorization reuse is the goal, not a verified capability for every runtime; see the [current-flow audit](DOCUMENTATION_AUDIT.md).
5. Inside project settings, the user creates a board from the default versioned workflow. The board copies the latest saved role assignments and concurrency limit; later project edits do not rewrite that snapshot.
6. The user adds a Draft task directly or asks one assigned role to analyze project files. A planning request creates a hidden run, verifies the saved agent authorization or performs the runtime's isolated setup, grants read-only/network-denied access, and pauses with source-cited proposals. The user selects which proposals become Draft cards; provider output never creates tasks without that review.
7. The user refines a Draft task and marks it Ready. **Prepare run** snapshots the board's workflow, role assignments, and saved-agent references plus trusted project policy, then creates the feature branch and owned worktree. Before launch, the run page verifies authorization. Cuckoding never copies credentials into snapshots; provider-owned storage depends on the runtime and legacy versus saved-account setup.
8. The current launcher moves through Specifications → Coding → Review and waits for human release approval. The accepted target adds Review returns to Specifications/Coding and local completion without release; those branches are not yet integrated into the launcher. See [FLOW.md](FLOW.md).
9. Each stage produces typed artifacts and must pass its exit gate; relevant project knowledge is injected and its use recorded.
10. The global dashboard lists recent operations from the durable run projection, including queued runs before an agent session exists, and refreshes role, runtime, elapsed-time, resource, and attention data after committed events. Agent Floor provides the session-level view; the laptop can sleep and wake without corrupting the run.
11. On completion or archive, the user runs consolidation, reviews candidates, and publishes project or global knowledge and skills.

## Success metrics

- At least 95% of interrupted runs (crash, quit, sleep, power loss) recover without manual database repair.
- Every external process is attributable to one project, board, task, run, stage, and agent session.
- A user can identify the cause of a blocked stage from the UI within two minutes.
- No global knowledge item exists without source evidence and an approval record; every injected knowledge item has a usage record.
- No agent process receives a Cuckoding-managed secret outside its declared capability set.
- Median time from feature creation to first specification artifact is under two minutes, excluding provider queue time.
- Reported API cost reconciles with provider-reported usage within the known limitations documented per adapter.
- A run that spans at least one sleep/wake cycle completes with the gap recorded and no duplicate stage execution.

## Commercial path

The local application can support a paid product through advanced workflows, enterprise policy packs, container and remote runners, team synchronization, SSO, audit export, centralized budgets, and managed knowledge catalogs. The open core keeps local execution, core orchestration, basic adapters, and the plugin system useful without a subscription. The name, license, and pricing hypotheses and their review dates are recorded in `docs/MVP_BOUNDARY_AND_POSITIONING.md` and ADR-018 through ADR-020.
