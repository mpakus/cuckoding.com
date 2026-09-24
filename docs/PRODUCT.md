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
2. Add a project through a short guided setup for its name, native-selected folder, and Git base branch. The folder may be empty, an unborn Git repository, or an existing project.
3. Create several independent boards for a project, such as product features, maintenance, and security remediation.
4. Assign saved agents to project roles and apply those roles to boards before starting delivery runs.
5. Add tasks manually or ask one assigned agent to inspect project documentation and propose tasks; review the proposals before importing them as Draft cards.
6. Start the project to admit independent Ready tasks concurrently through Speculator, Implementor, and Reviewer, within board, project, and machine limits. Human completion and release decisions remain explicit; the current launcher differences are recorded below.
7. Watch on the global dashboard and Agent Floor which role and runtime is doing what, without exposing private reasoning.
8. Open each run's worktree and local preview URL.
9. Pause, hibernate, retry, or stop work without losing durable state.
10. Inspect changes, test results, review findings, cost, tokens, cache behavior, CPU, and memory.
11. Produce a branch and optional draft pull request for human review.
12. Compress completed work into reviewed project knowledge and skills, see the knowledge base grow, and see where it was used and whether it helped.
13. Plug in tools already installed on the machine (XERJ, RTK, Ponytail, MCP servers, container runtimes) through connectors.

## Default roles and extensibility

The accepted product contract, clarified on 2026-09-24, has three default agent
roles. **Implementor** is the canonical display name.

| Role | Responsibility | Handoff |
| --- | --- | --- |
| Speculator | Create specifications and task descriptions from the user's prompt or the project's `.md` plan files; define scope and testable acceptance criteria | Give Implementor the task description and specs; revise them against Reviewer comments on a return |
| Implementor | Implement code and tests against the task description and specs | Give Reviewer the changes, implementation summary and test evidence |
| Reviewer | Independently review the implementation and report to Cuckoding whether the task is done or needs revision | Return an explicit result and a list of review comments; Cuckoding sends work needing revision back to Speculator |

The revision loop is **Speculator → Implementor → Reviewer → Speculator** until
review passes or the configured attempt/budget limit requires attention.
Cuckoding validates and persists the result and performs transitions; provider
text alone cannot mark a task done. A passing review keeps the existing human
local-completion or release-approval boundary.

Roles are extensible: users can create more roles, assign agents and configure
additional permissions. Permission changes require explicit trusted policy
configuration and approval within supported runtime capabilities; role names,
instructions and project plan files cannot grant themselves access. Historical
board/run snapshots retain their original roles and permissions.

**Implemented in task 1038:** new project defaults use these three names with
stable keys `spec_writer`, `implementer` and `reviewer`. New default workflows
return both intent and code corrections to Speculator. Every stage receives
the task description; Implementor and Reviewer also receive the latest generated
specification. A returning Speculator receives its prior spec and the validated
review comments/evidence. Per-attempt specifications remain durable artifacts.
Existing boards/runs keep their original names and versioned routing; creating
a new board uses the latest default without rewriting the old definition.

**Implementation gap:** project settings already save custom role names,
instructions and assignments, but adding a role does not insert an
executable workflow stage, and there is no dedicated role-permission editor.
Read-only planning can inspect committed Markdown named in a prompt and propose
tasks for human import; that is not full acceptance of the Speculator contract.
See [FLOW.md](FLOW.md#intended-default-feature-flow) and the unchecked work in
[PLAN.md](PLAN.md#role-contract-alignment--2026-09-24).

## MVP capabilities

These describe current source and its limits; the role-contract changes above
remain pending where explicitly identified.

- Local project registry with separate add/edit setup; creating a project does not create a board, task, run, branch, or worktree.
- A machine-wide saved-agent catalog plus project role defaults. A three-step add flow collects name/runtime, discovers an installed executable and verifies reusable authorization, then offers provider-discovered models and supported Codex reasoning levels. New built-in roles are Speculator, Implementor, and Reviewer; users may attach the same saved agent to several projects, add roles, and edit role names/instructions. Successful Codex and Cursor authorization checks refresh a bounded provider model catalog for the shared sign-in. Output contracts belong to workflow/adapter configuration. The catalog stores connection metadata, authorization status, and validated model labels/IDs, never credential values or raw provider output.
- Multiple boards and concurrent task flows per project.
- Durable project Start/Pause/Needs attention/Done control with a per-project run limit and open blocker-finding threshold. Pause stops new starts, not already-running work. Boards can be created before agents are assigned; assigning current project roles to a board updates future runs and adds audited saved-agent bindings to compatible queued runs without rewriting their snapshots.
- Read-only board planning runs that turn a bounded prompt into source-cited task proposals; only human-selected proposals become Draft tasks.
- Validated workflow definitions and role-to-runtime assignment; the creation UI selects the default workflow. Custom stage/permission editing and execution of added roles remain gaps against the contract above.
- Claude Code, Codex, and Cursor Agent as supported launch adapters. Saved Codex/Cursor agents can share an app-owned provider sign-in while selecting different models; per-run configuration stays separate. Cursor refuses project MCP, sandbox, CLI, or plugin overrides. Project setup may also save OpenCode and Custom Agent connections, but task execution remains blocked until a reviewed adapter passes the conformance suite.
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

**Agent setup (task 1018, implementation delivered; real-provider acceptance pending):**
Add and authorize agents once in machine-wide **Agents** management; projects
select those connections and assign roles. Run start automatically checks each
distinct connection and asks for reconnect only when needed. The detailed
[agent-first flow](AGENT_AUTHORIZATION_FLOW.md) documents the app-owned shared
profiles, provider-history sharing and remaining acceptance checks.

1. The user clicks the menubar icon → Cuckoding; the global dashboard opens with registered projects, health, resources, active work, and attention items.
2. The user chooses **Add project** or edits an existing project.
3. A three-step wizard collects project identity and a system-selected project folder plus Git base branch, then reviews the pending registration. Before confirmation it only inspects the folder. After explicit review, it initializes Git and creates the first local commit when no branch revision exists; an existing repository with the selected branch is not changed.
4. Confirming the wizard registers only the project and redirects to its settings page. There the user can add or reuse multiple saved agents, configure provider-specific authorization, edit or add roles, and assign one connection to each role. Every project save creates an immutable trusted configuration revision; it does not create or start work. One-time authorization reuse is the goal, not a verified capability for every runtime; see the [current-flow audit](DOCUMENTATION_AUDIT.md).
5. Inside project settings, the user creates a board from the default versioned workflow. The board copies the latest saved role assignments and concurrency limit. Later project edits do not silently rewrite the board; **Assign agents to board** explicitly updates future runs and connects compatible queued work through append-only binding events.
6. The user adds a Draft task directly or asks one assigned role to analyze project files. A planning request creates a hidden run, verifies the saved agent authorization or performs the runtime's isolated setup, grants read-only/network-denied access, and pauses with source-cited proposals. The user selects which proposals become Draft cards; provider output never creates tasks without that review.
7. The user refines a Draft task and marks it Ready. If project automatic work is running, the dispatcher admits eligible Ready tasks within its limits; otherwise the user can choose **Prepare run** manually. The board shows current admission delays, such as an unmet dependency or capacity limit. Preparation snapshots the board's workflow, role assignments, and saved-agent references plus trusted project policy, then creates the feature branch and owned worktree. Before launch, the run page verifies authorization. Cuckoding never copies credentials into snapshots; provider-owned storage depends on the runtime and legacy versus saved-account setup.
8. New default workflows move through Speculator → Implementor → Reviewer. Error or blocker findings return to Speculator with their comments/evidence, then repeat downstream stages within a three-Review budget. Legacy run snapshots retain their previous routing. A passing Review currently waits for a human choice: complete locally without a push, or approve the host-side release handoff. Automatic local completion and the rest of the full-flow goal remain task 1038 work. See [FLOW.md](FLOW.md).
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
