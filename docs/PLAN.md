# Implementation Plan

The plan is organized as gated phases. Task files under `tasks/` provide the detailed implementation units. A phase is complete only when its outcomes are demonstrated and every exit checklist item is true. The walking skeleton at the end of Phase 4 is the first checkpoint where the product is judged before more infrastructure is built.

## Phase 0 — Discovery and feasibility

**Outcome:** agreed MVP boundary, competitive position, trusted-host threat model, and proof that one agent runtime, the menubar shell, and sleep/wake handling work on macOS Apple Silicon.

- [x] Record product boundaries, competitors, name/license/pricing hypotheses, and threat model.
- [x] Spike one agent runtime on the host in a worktree with permissions, cancel, and resume.
- [x] Spike the menubar shell launching a bundled release and opening the browser. Protocol, clean-account, browser-handoff, and shutdown checks pass.
- [x] Spike sleep/wake detection and power assertions. Simulated, software-sleep, AC lid-close, and battery recovery checks pass.
- [x] Record findings and revise decisions.
- [x] Audit the planning pack and establish RTK/XERJ reference coding.
- [x] Place repository skills/configuration at root and verify the local toolchain.

## Phase 1 — Phoenix foundation

**Outcome:** a testable Phoenix/LiveView application with SQLite, supervision, durable commands, and local developer tooling.

- [x] Create the Phoenix application and quality gates.
- [x] Configure SQLite durability and migrations.
- [x] Implement append-only events and durable command dispatch.
- [x] Add process registry, supervision, leases, and correlation IDs.

## Phase 2 — Domain and persistence

**Outcome:** projects, boards, tasks, workflows, runs, attempts, approvals, artifacts, events, and secrets survive restarts.

- [x] Implement schemas and domain commands.
- [x] Enforce versioned workflow and policy snapshots.
- [x] Implement idempotent transitions and event sequencing.
- [x] Implement startup reconciliation and recovery.
- [x] Implement Keychain-backed `SecretStore` and redaction.

## Phase 3 — Local workspaces and process runner

**Outcome:** confined worktrees, supervised host processes, ports and preview URLs, hibernate/resume, and power handling.

- [x] Git worktree lifecycle and path confinement.
- [x] `LocalProcessRunner` with process groups, environment allowlist, timeouts.
- [x] Command policy and protected paths.
- [x] Port allocation and preview URLs.
- [x] Pause, hibernate, resume, safe cleanup.
- [x] Power assertions and sleep/wake reconciliation.

## Phase 4 — Agent adapters and walking skeleton

**Outcome:** normalized adapters and one end-to-end thin slice.

- [x] Adapter behaviour, fake adapter, conformance suite.
- [x] Claude Code, Codex, and run-scoped Cursor Agent adapters.
- [x] Cursor Agent adapter and OpenCode stable stub.
- [x] Walking skeleton: fake CI plus an isolated real-Codex demo cover sleep/resume, approval UI, evidence, and local-bare-remote release.

## Phase 5 — Workflow engine and Kanban

**Outcome:** tasks move through configurable durable workflows across multiple boards.

- [x] Workflow validation and transition evaluation.
- [x] Accessible Kanban and task detail.
- [x] Multiple boards, dependencies, budgets, concurrency, unattended mode.
- [x] Gates, human approval, host-side release handoff.

## Phase 6 — Agent Floor and telemetry

**Outcome:** users see who is doing what, what it costs, and what happened during sleep.

- [x] Normalized activity stream.
- [x] Host resource metrics and rollups.
- [x] Usage and cost accounting with confidence labels.
- [x] Agent Floor, run detail, agent inspector.

## Phase 7 — Knowledge

**Outcome:** evidence becomes reviewed project and global knowledge and skills; use is visible.

- [x] Knowledge store, front matter, index sync.
- [x] Per-run extraction with memory operations.
- [x] Consolidation jobs and redaction.
- [x] Review queue, publication, skill packaging, revocation.
- [x] Injection into runtimes and usage tracking.
- [x] Knowledge Growth and Lineage/Usage views.

## Phase 8 — Plugin system

**Outcome:** optional tools connect through manifests without touching the core.

- [x] Manifest schema, discovery, registry, health, enablement.
- [x] Behaviours and conformance suites per kind.
- [x] Reference plugins: RTK, Ponytail, XERJ, generic MCP server.
- [x] Container runner plugin contract and stub.

## Phase 9 — Shell and packaging

**Outcome:** a signed, notarized, updateable macOS build with the menubar shell.

- [x] Menubar shell and handshake.
- [x] Release bundling, signing, notarization.
- [x] Updater, backups, migrations, rollback.
- [x] Login item and diagnostics bundle.

## Phase 10 — Hardening and beta

**Outcome:** the product withstands common threats and recovers predictably; controlled external testing.

- [x] Capability and secret hardening, adversarial prompt and plugin tests.
- [x] Crash, power-loss, and sleep recovery drills.
- [x] Task 1008: safe public-message boundary and actionable empty states across
  Phoenix UI surfaces; raw internal errors are excluded from browser alerts.
- [x] Complete the accepted project-first product flow:
  - [x] Global dashboard lists projects, health, resources, active work, and attention.
  - [x] Add-project wizard separates identity, repository/branch, and review; project settings versions multiple agents and role assignments.
  - [x] Project settings creates boards independently from project registration.
  - [x] Board task creation and run preparation use the default Specifications → Coding → Review workflow and copied board role assignments.
  - [x] Board prompts create planning runs; validated, user-selected proposals become Draft tasks.
  - [x] Saved machine-local agent metadata can be attached across projects without rewriting old board/run snapshots.
  - [x] Task 1020: host-validated Review findings rerun Specifications/Coding within a fixed budget; passing runs can complete locally without release or continue to approved handoff.
- [ ] Task 1018: complete real-provider acceptance of [agent-first authorization](AGENT_AUTHORIZATION_FLOW.md). Global management, shared profiles, automatic checks, grouped roles and explicit legacy bindings are implemented and regression-tested. Cursor's isolated-HOME Keychain failure is fixed by its native app-owned file credential store; a repeated login and authenticated cross-project run remain required evidence.
- [x] Task 1019: reuse a compatible provider sign-in across named agents by default; select each agent's model independently and preserve it in planning/workflow requests. Additive migration and regression checks preserve existing accounts. Provider-controlled expiry and real authenticated concurrency remain task 1018 gates.
- [ ] Verify one saved login across isolated runs in two projects for each supported runtime, including refresh/restart/revocation and concurrency; current configuration tests are not proof of credential reuse.
- [x] Complete shared-account revocation UX and per-project impact lists. The
  confirmed provider-scoped logout records value-free request/completion events, blocks new
  launches for linked agents, and preserves running work and historical snapshots.
- [ ] Dogfood and controlled beta.
- [ ] MVP release readiness.

Remaining gate order: finish real-provider and shared-account lifecycle evidence;
run controlled beta; then execute task 1004 against one frozen signed release
candidate. Automated tests never substitute for those external acceptance gates.

## Definition of done for MVP

The [current-flow audit](DOCUMENTATION_AUDIT.md) separates implemented UI/domain
surfaces from real-provider and release evidence. Custom workflow/board editors
and execution through OpenCode/Custom Agent are not shipped capabilities.

- [ ] Two supported agent runtimes complete the default workflow on the host runner.
- [ ] Two boards run concurrently without worktree, port, process, or event crossover.
- [x] A running task survives hibernate, app quit, relaunch, and a real sleep/wake cycle with a single execution of each stage.
- [ ] The Agent Floor attributes every action to a role, runtime, model, and run.
- [ ] Provider-reported and estimated costs are visually distinguishable; active and wall time are both shown.
- [ ] A failed QA gate returns structured findings to development.
- [ ] Human approval triggers a host-side release handoff that pushes a branch and creates a draft PR.
- [ ] A completed run yields knowledge candidates; consolidation and publication require the documented approvals; the next run records knowledge usage; both dashboard views render.
- [ ] RTK, XERJ, Ponytail, and a generic MCP plugin can be enabled, contribute labeled results, and be removed without breaking core.
- [ ] A clean supported Mac installs, starts from the menubar, executes a sample project, updates, and uninstalls safely.
