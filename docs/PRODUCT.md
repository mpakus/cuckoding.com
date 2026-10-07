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
4. Save a default team once; new projects inherit its role settings. Existing projects retain their assignments and optional overrides.
5. Describe a project goal to produce independently reviewed Draft tasks, then press Run to authorize local delivery. Manual task creation/intake remains available in board controls.
6. Start a board's Draft/Ready batch sequentially with Speculator coordination and reviewed commit handoff, or start the project to admit independent Ready tasks concurrently. Both respect board, project and machine limits; local completion follows the recorded authorization and external release remains separate.
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
text alone cannot mark a task done. A passing review follows the user's recorded
choice: wait for a completion decision, or complete locally automatically.
Remote release approval remains separate.

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

Custom roles can remain planning-only or run after Speculator or Implementor,
in displayed order. Delivery permissions offer read-only inspection/checks or
worktree writes/checks; the built-in Speculator and Reviewer remain read-only.
Saving a changed schedule or grant requires confirmation and records an audit
event. New boards copy it; explicitly applying project roles updates an existing
board's future flow. Prepared and historical runs keep their snapshots.
Additional-role reports pass to downstream roles and the final Reviewer, are
hashed evidence artifacts, and repeat within the bounded correction loop.
The final Reviewer still controls pass/correction through Cuckoding.

This is a supported extension of the default flow, not an arbitrary graph,
external-path or network-permission editor. Runtime-specific enforced and
unenforced permissions remain visible. Read-only planning can inspect committed
Markdown named in a prompt and propose tasks for human import; rendered native
and real-provider acceptance of the full flow remains open.
See [FLOW.md](FLOW.md#intended-default-feature-flow) and the remaining acceptance in
[PLAN.md](PLAN.md#role-contract-alignment--2026-09-24).

## MVP capabilities

These describe current source and its limits, not acceptance of an installed
release. Real-provider/native checks remain open where explicitly identified.

- Local project registry with separate add/edit setup; creating a project does not create a board, task, run, branch, or worktree.
- A machine-wide saved-agent catalog plus project role defaults. A three-step add flow collects name/runtime, discovers an installed executable and verifies reusable authorization, then offers provider-discovered models and supported Codex reasoning levels. New built-in roles are Speculator, Implementor, and Reviewer; users may attach the same saved agent to several projects, add roles, and edit role names/instructions. Successful Codex and Cursor authorization checks refresh a bounded provider model catalog for the shared sign-in. Output contracts belong to workflow/adapter configuration. The catalog stores connection metadata, authorization status, and validated model labels/IDs, never credential values or raw provider output.
- Multiple boards and concurrent task flows per project.
- **Start board** reviews existing Draft/Ready delivery cards as a fixed batch and explicitly authorizes automatic local completion. The assigned read-only Speculator proposes each next step; Cuckoding validates priority, dependencies, permissions and capacity, runs one delivery task at a time, and passes reviewed commits forward. The first hard blocker halts the batch. Board Pause/Resume/Stop/Skip/Retry and confirmed pending-request refresh retain evidence; skipped prerequisites defer descendants. Board/home progress and complete batch accounting include controller work and retries. Source, fixture and browser evidence is recorded in [CUCKODING-CONTROL.md](CUCKODING-CONTROL.md); real-provider and packaged-app acceptance remains open.
- Opt-in **Plan and execute** in the board modal: goal/criteria, reviewed task import with the saved team, reviewed revisions for unstarted work, bounded recovery and role conversations. Independent tasks continue around task-local blockers; unresolved work retains Needs attention. Fixed batches remain the default. See [the autonomous contract](CUCKODING-CONTROL.md#autonomous-goals-task-1055) and [task 1055 evidence](../worklog/2026-09-28-1055-autonomous-board.md); provider/native acceptance is separate.
- Durable project Start/Pause/Needs attention/Done control with a per-project run limit and open blocker-finding threshold. Pause stops new starts, not already-running work. Boards can be created before agents are assigned; assigning current project roles to a board updates future runs and adds audited saved-agent bindings to compatible queued runs outside a board batch without rewriting their snapshots.
- Run-level Pause/Resume/Stop and dashboard-wide Pause all/Resume workspace/Stop all. Workspace controls gate new launches durably, suspend verified running process groups, and retain branches/worktrees/evidence on stop. Individual pauses survive a global resume. A stopped task can prepare a new run; missing live workers fail resume closed. These controls have source/fixture checks; native/provider acceptance remains open.
- Read-only board planning runs that turn a bounded prompt into source-cited task proposals. Before import, another snapshotted role with a different configured model/runtime can review them, revise descriptions/specs and save per-task comments and a Markdown report. Proposal IDs and before/after history are preserved. The guided project goal imports accepted tasks after independent review and host validation. The advanced planning path still imports only human-selected proposals.
- Validated workflow definitions and role-to-runtime assignment; the creation UI selects the default workflow extended by explicitly scheduled custom roles and their saved worktree permissions. Arbitrary workflow graph editing remains outside this UI.
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

Task 1057 adds **Default team** in Agents: choose the three saved role connections
once, with role instructions and finite limits. New project registration copies
that revision; older projects and runs remain unchanged. The same saved agent can
fill all roles in separate sessions. Saving defaults starts no work.
The project goal screen also creates/reuses a delivery board, plans and reviews
Draft tasks automatically, persists Ready to run, and records a separate immutable
Run authorization. Brief edits require another plan review; replays and reconnects
retain the same work. A goal-wide elapsed deadline includes planning and waiting,
with remaining time bounding each process launch. Run displays the validated
setup/check commands and verified native tool paths. Preparation checks versions
in an isolated environment before Ready, without requiring personal shell setup.
Final verification executes commands at the reviewed head and
assesses every original criterion in an independent session. A passed task review
is not presented as a passed test. Failed final checks return to bounded automatic
repair planning. Known-ended interruptions resume with saved evidence and separate
finite retry/wait/continuation counters. When all remaining tasks have classified
failures, the team can review a different approach without resetting their budgets.
Genuine questions name the affected criterion and what the team already checked;
the project screen retains entered answers across updates. Real-provider/native
acceptance remains in progress in
[task 1057](../tasks/phase-10-hardening-beta/1057-autonomous-project-flow.md).

1. The user clicks the menubar icon → Cuckoding; the global dashboard opens with registered projects, health, resources, active work, and attention items.
2. The user chooses **Add project** or edits an existing project.
3. A three-step wizard collects project identity and a system-selected project folder plus Git base branch, then reviews the pending registration. Before confirmation it only inspects the folder. After explicit review, it initializes Git and creates the first local commit when no branch revision exists; an existing repository with the selected branch is not changed.
4. Confirming the wizard registers only the project. With a saved default team it opens the project brief screen; otherwise it opens project settings for agent assignment. Every project save creates an immutable trusted configuration revision; registration does not create or start work. One-time authorization reuse remains a separate real-provider acceptance gate; see the [current-flow audit](DOCUMENTATION_AUDIT.md).
5. With a saved default team, registration opens the project brief. **Create plan** authorizes read-only planning and independent review, imports the accepted Draft tasks, and waits at Ready to run. That path does not ask for another role assignment, a new board, or manual proposal selection.
6. **Run** authorizes that exact plan, the saved team, finite limits, in-scope corrections, and automatic local completion. The screen keeps Pause, Stop, and Inspect available. When the goal is Done, it shows the reviewed commit, local branch, worktree, criterion evidence, and a loopback preview when the run has one. Finder and the editor open that recorded worktree. Push, pull request, and merge stay separate approvals.
7. Needs you is reserved for an outcome-changing question, missing authorization, a new capability, an exhausted limit, uncertain process ownership, or a protected-path or policy change. Ordinary reversible choices stay recorded assumptions and do not stop the goal.
8. Advanced settings still create boards, assign agents, add Draft tasks, and run human-selected proposal import. **Start board** reviews a fixed Draft/Ready batch, its dependency-aware order, roles/models, budgets and base revision, then authorizes automatic local completion for that batch. The assigned Speculator proposes each next step; Cuckoding validates it, admits one delivery task and promotes Draft to Ready only before its authorized execution. Newly added cards wait for another batch. On an unclaimed board the user can mark a card Ready and use project automatic admission or **Prepare run → Start workflow**. Every path verifies authorization and snapshots trusted configuration before provider work; snapshots contain references, never credentials. Later project edits do not silently rewrite a board; **Assign agents to board** explicitly updates future runs.
9. New default workflows move through Speculator → Implementor → Reviewer. Error or blocker findings return to Speculator with their comments/evidence, then repeat downstream stages within a three-Review budget. Legacy run snapshots retain their previous routing; Start board requires the compatible correction flow. Board batches complete passing tasks locally and start the next worktree from the reviewed commit. Manual/project starts default to waiting for a completion decision, with automatic local completion available as an explicit choice. None authorizes push, PR creation or merge. See [FLOW.md](FLOW.md) and [CUCKODING-CONTROL.md](CUCKODING-CONTROL.md).
10. Each stage produces typed artifacts and must pass its exit gate; relevant project knowledge is injected and its use recorded.
11. The global dashboard lists recent operations, including queued runs before a session exists, and mirrors board-batch progress. The board shows current/next work, complete membership and available accounting, plus Pause/Resume/Stop/Skip/Retry controls. A hard blocker halts a fixed batch; a guided goal continues independent work around a task-local blocker. Skip retains changes and defers dependent descendants. Agent Floor provides the session view. Startup and wake reconciliation use durable records; ambiguous ownership or missing checkpoints require attention rather than an assumed resume. Physical-machine acceptance for recovery during an active provider prompt remains open.
12. On completion or archive, the user runs consolidation, reviews candidates, and publishes project or global knowledge and skills.

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
