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
- [ ] Implement Keychain-backed `SecretStore` and redaction.

## Phase 3 — Local workspaces and process runner

**Outcome:** confined worktrees, supervised host processes, ports and preview URLs, hibernate/resume, and power handling.

- [ ] Git worktree lifecycle and path confinement.
- [ ] `LocalProcessRunner` with process groups, environment allowlist, timeouts.
- [ ] Command policy and protected paths.
- [ ] Port allocation and preview URLs.
- [ ] Pause, hibernate, resume, safe cleanup.
- [ ] Power assertions and sleep/wake reconciliation.

## Phase 4 — Agent adapters and walking skeleton

**Outcome:** normalized adapters and one end-to-end thin slice.

- [ ] Adapter behaviour, fake adapter, conformance suite.
- [ ] Claude Code and Codex adapters.
- [ ] Cursor Agent and OpenCode adapters or stable stubs.
- [ ] Walking skeleton: spec → development → review → branch with one adapter and a minimal UI.

## Phase 5 — Workflow engine and Kanban

**Outcome:** tasks move through configurable durable workflows across multiple boards.

- [ ] Workflow validation and transition evaluation.
- [ ] Accessible Kanban and task detail.
- [ ] Multiple boards, dependencies, budgets, concurrency, unattended mode.
- [ ] Gates, human approval, host-side release handoff.

## Phase 6 — Agent Floor and telemetry

**Outcome:** users see who is doing what, what it costs, and what happened during sleep.

- [ ] Normalized activity stream.
- [ ] Host resource metrics and rollups.
- [ ] Usage and cost accounting with confidence labels.
- [ ] Agent Floor, run detail, agent inspector.

## Phase 7 — Knowledge

**Outcome:** evidence becomes reviewed project and global knowledge and skills; use is visible.

- [ ] Knowledge store, front matter, index sync.
- [ ] Per-run extraction with memory operations.
- [ ] Consolidation jobs and redaction.
- [ ] Review queue, publication, skill packaging, revocation.
- [ ] Injection into runtimes and usage tracking.
- [ ] Knowledge Growth and Lineage/Usage views.

## Phase 8 — Plugin system

**Outcome:** optional tools connect through manifests without touching the core.

- [ ] Manifest schema, discovery, registry, health, enablement.
- [ ] Behaviours and conformance suites per kind.
- [ ] Reference plugins: RTK, Ponytail, XERJ, generic MCP server.
- [ ] Container runner plugin contract and stub.

## Phase 9 — Shell and packaging

**Outcome:** a signed, notarized, updateable macOS build with the menubar shell.

- [ ] Menubar shell and handshake.
- [ ] Release bundling, signing, notarization.
- [ ] Updater, backups, migrations, rollback.
- [ ] Login item and diagnostics bundle.

## Phase 10 — Hardening and beta

**Outcome:** the product withstands common threats and recovers predictably; controlled external testing.

- [ ] Capability and secret hardening, adversarial prompt and plugin tests.
- [ ] Crash, power-loss, and sleep recovery drills.
- [ ] Dogfood and controlled beta.
- [ ] MVP release readiness.

## Definition of done for MVP

- [ ] Two supported agent runtimes complete the default workflow on the host runner.
- [ ] Two boards run concurrently without worktree, port, process, or event crossover.
- [ ] A running task survives hibernate, app quit, relaunch, and a real sleep/wake cycle with a single execution of each stage.
- [ ] The Agent Floor attributes every action to a role, runtime, model, and run.
- [ ] Provider-reported and estimated costs are visually distinguishable; active and wall time are both shown.
- [ ] A failed QA gate returns structured findings to development.
- [ ] Human approval triggers a host-side release handoff that pushes a branch and creates a draft PR.
- [ ] A completed run yields knowledge candidates; consolidation and publication require the documented approvals; the next run records knowledge usage; both dashboard views render.
- [ ] RTK, XERJ, Ponytail, and a generic MCP plugin can be enabled, contribute labeled results, and be removed without breaking core.
- [ ] A clean supported Mac installs, starts from the menubar, executes a sample project, updates, and uninstalls safely.
