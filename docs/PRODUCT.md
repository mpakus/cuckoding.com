# Product Specification

## Vision

Cuckoding is a visual, local-first operating system for coding-agent work on a developer's Mac. It turns an issue into a durable multi-stage process, assigns each stage to an agent role and runtime, keeps the work alive for hours or days, and exposes the state, evidence, cost, resource load, accumulated knowledge, and controls in one browser dashboard reachable from a menubar icon.

It is not a chat client and it is not an autonomous merge bot. Its product value is coordination, durability, evidence, and compounding project knowledge.

## Target users

- Individual developers using two or more coding agents who want to run several features in parallel without babysitting terminals.
- Small teams that need repeatable agent workflows without moving private repositories to a hosted control plane.
- Engineering leads comparing model/runtime performance and cost across real tasks.
- Security-sensitive teams that require local execution and inspectable audit trails.

## Core jobs to be done

1. Connect a repository folder and describe how it may be built, tested, run, and modified.
2. Create several independent boards for a project, such as product features, maintenance, and security remediation.
3. Configure a workflow and map roles to installed agent runtimes and models.
4. Add tasks, approve them for execution, and let them progress through gates for as long as they need, including across laptop sleep.
5. Watch on the Agent Floor which role and runtime is doing what, without exposing private reasoning.
6. Open each run's worktree and local preview URL.
7. Pause, hibernate, retry, or stop work without losing durable state.
8. Inspect changes, test results, review findings, cost, tokens, cache behavior, CPU, and memory.
9. Produce a branch and optional draft pull request for human review.
10. Compress completed work into reviewed project knowledge and skills, see the knowledge base grow, and see where it was used and whether it helped.
11. Plug in tools already installed on the machine (XERJ, RTK, Ponytail, MCP servers, container runtimes) through connectors.

## MVP capabilities

- Local project registry and Git repository connection.
- Multiple boards and concurrent task flows per project.
- Configurable stage templates and role-to-runtime assignment.
- Claude Code and Codex as supported launch adapters; Cursor Agent and OpenCode retain stable contracts and test doubles until their conformance suites pass.
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

1. The user clicks the menubar icon → Cuckoding; the dashboard opens in the browser.
2. The user creates a project and selects a local Git repository folder.
3. Cuckoding validates the repository, project policy, toolchain, installed runtimes, and plugins.
4. The user creates a board from a workflow template and adds a feature.
5. The user assigns roles or accepts board defaults.
6. Cuckoding creates a worktree, branch, port allocation, and process group, then starts the specification stage.
7. Each stage produces typed artifacts and must pass its exit gate; relevant project knowledge is injected and its use recorded.
8. The Agent Floor streams who is doing what; the laptop can sleep and wake without corrupting the run.
9. Failed gates return the task to the configured stage with findings attached.
10. Human approval triggers the host-side release stage: push and draft PR.
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
