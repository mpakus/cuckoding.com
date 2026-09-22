# Autonomous project flow — implementation and remaining gates

Status: **project-level automatic admission implemented for testing** on
2026-09-22. The baseline audit below describes `main` at `4546f85` before
task 1029. Current operation is described in [FLOW.md](FLOW.md); the remaining
gates below are not claims of full unattended completion.

## Implemented in task 1029

- Boards can be created before assigning agents. After saving project roles,
  **Apply project roles** updates an existing board for future runs; historical
  run snapshots are unchanged.
- Project settings provide **Start project**, **Pause new starts**, a project
  concurrency limit, blocker threshold, durable state and progress. The global
  dashboard shows each project's operation state and attention reason.
- A supervised worker periodically reads durable running controls and admits
  Ready delivery tasks through `Scheduler.plan/1`, `ProjectWorkflow.prepare_task/1`,
  and `GuidedRun.start/1`. Queued runs can resume admission after restart.
  Admission respects board, project and global running limits; duplicate active
  run creation is checked in the SQLite transaction.
- Distinct blocked delivery tasks with open `blocker` findings on their active
  runs count toward the project threshold. Preparation/start failures and unmet
  prerequisite deadlocks move the project to **Needs attention**. A project is
  **Done** only when every delivery task is done.
- Start does not auto-import agent proposals, approve policy changes, complete
  a passing review, push, create a PR, or merge. Pause only stops new starts;
  active runs continue. OpenCode and Custom Agent remain setup-only.

Still to verify on a signed clean macOS build: long-running real-provider
concurrency, restart/sleep recovery, and shared-authorization refresh. The
human completion decision and whether non-review failures count toward the
critical threshold remain product decisions.

## User story

As a solo developer, I connect and authorize each agent once, choose its model
and reasoning level where supported, then register a local project and create a
board. I add tasks myself or ask an agent to propose them from Markdown specs in
the project. I assign saved agents to the project's workflow roles, set the
project's concurrency and critical-blocker limit, and press **Start project**.
Cuckoding then admits Ready tasks autonomously, running independent tasks in
parallel up to those limits. Within each task, Specifications writes a spec,
Coding implements it, and Review checks it; findings route back to the
responsible stage. As agents become available, more eligible tasks start. The
project stops admitting work when every task is complete, I pause it, a safety
gate needs my decision, or the configured critical-blocker threshold is met.
I can see the reason, current owner, and evidence on the board and dashboard.

## Baseline before task 1029

| Journey step | Current behavior | Gap |
| --- | --- | --- |
| Save agents, authorize once, select models | The three-step Agents wizard exists; named agents can share a provider sign-in and retain independent model settings (`agent_settings_live.ex`, `agent_runtime.ex`). | Real authenticated cross-project execution, refresh, and concurrency remain acceptance gates in [AGENT_AUTHORIZATION_FLOW.md](AGENT_AUTHORIZATION_FLOW.md). OpenCode and Custom Agent remain setup-only. |
| Add project and folder | Project → Repository → Review uses a native folder chooser and can initialize an empty/unborn Git folder (`project_setup_live.ex`). | This part matches the story. |
| Create board and tasks | Project settings creates a board with a concurrency limit; the board adds Draft tasks. A read-only planning run can inspect Markdown files, but only selected proposals become Draft cards (`project_edit_live.ex`, `board_live.ex`, `board_task_intake.ex`). | The planning run and proposal import require separate manual actions. Ready tasks must also be marked manually. This review is intentional: model output is untrusted. |
| Assign agents to roles | Project settings saves role defaults. Board creation copies them; later edits do not automatically change existing boards (`project_workflow.ex:71`, `project_edit_live.ex:239`). | The requested “tasks first, assign roles, then Start” order is awkward. An existing board has a limited **Connect saved agents** action, not a complete board-role editor or a clear pre-start configuration review. Custom roles are not run by the default launcher. |
| Start and parallel work | A Ready task requires **Prepare run** on its detail page, followed by **Start workflow** on its run page (`task_live.ex:148`, `run_live.ex:85`). `Scheduler.plan/1` can rank Ready tasks using dependencies, board/project/global limits, ports, and memory (`execution/scheduler.ex:90`). | There is no project/board **Start** action, durable project execution mode, or production caller for `Scheduler.dispatch/1`. The stored concurrency limit is admission data, not an autonomous launch loop. |
| Specifications → Coding → Review | One started run performs these stages sequentially. Review findings can loop to Specifications or Coding; the fixed Review ceiling is three attempts (`walking_skeleton.ex:86-176`). | Independent tasks are not automatically prepared or started when capacity frees. There is no role-aware worker queue that assigns the next eligible stage to a free agent. |
| Stop on done or critical blockers | A passing Review waits for a human local-completion or release decision (`walking_skeleton.ex:120-131`). Failed runs block individually; a board has an unattended power window. | No project-wide completion controller, configurable critical-blocker threshold, or automatic stop-admission rule exists. Unattended mode does not waive approvals. |

Existing Phase 5 scheduler tests verify the *planner* and two-board admission,
not autonomous UI-to-provider dispatch. Therefore that baseline did **not**
yet deliver the requested hands-off project flow.

## Target behavior and remaining hardening

1. **Prepare.** In Agents, save/authorize connections and select models. Register
   a project and create a board without requiring final role assignments.
   Create Draft tasks manually or from reviewed, source-cited Markdown proposals.
2. **Configure.** Assign a saved agent to every required role on the board or
   apply current project defaults explicitly. Show a preflight with runnable
   adapters, live authorization, base branch, clean committed revision,
   dependencies, Ready task count, per-board and per-project concurrency,
   machine cap, critical-blocker threshold, budgets, and approval boundaries.
   Changes to roles/settings affect future runs only; never rewrite history.
3. **Start project.** One idempotent command persists a project execution state
   and audit event before scheduling. A supervised dispatcher repeatedly uses
   the existing scheduler to atomically claim eligible Ready tasks, prepare
   branches/worktrees, verify distinct saved sign-ins, and start their runs.
   Duplicate UI clicks, wake/restart, and competing ticks must not double-run a
   task. The remaining UI gap is per-task deferred reasons. Signed-build
   restart/sleep and cross-process admission races remain acceptance gates.
4. **Work.** Each task keeps its current Specifications → Coding → Review
   dependency order and review loops; separate tasks may run concurrently.
   Newly free capacity starts the next eligible task. Keep public specs,
   messages, findings, logs, and stage/agent/model/elapsed state on the task
   and run pages. Do not expose hidden reasoning. A saved sign-in is reused,
   while each run retains separate instructions, worktree, and evidence.
   Project Start grants no new filesystem, network, plugin, or secret access;
   every stage still receives its reviewed runtime permission grant. The host
   runner is not a sandbox.
5. **Stop or resume.** **Pause project** currently stops new admissions but
   does not checkpoint active work; **Resume** revalidates it. A proposed broader critical-blocker rule is
   to count distinct project tasks with an unresolved, host-validated
   `critical` finding or critical execution failure, not raw finding rows or
   retries. At threshold `N`, stop new admissions, request safe checkpoints for
   active runs, and show the counted tasks and recovery actions. Reset the
   count only after a human resolves/retries the blocker. Never kill or erase a
   worktree merely to reach the threshold. Show **Needs attention** when a
   policy/auth/budget/human gate prevents progress; do not label that **Done**.

### Product decisions needed before autonomous completion

- **Human completion gate.** Today every passing Review waits for a person.
  Full “until all tasks are done” autonomy requires a separately reviewed
  policy for *local-only* auto-completion after validated Review. The safer
  initial implementation stops at **Needs attention** for that choice. Neither
  option may automatically push, create a PR, merge, publish knowledge, or
  approve a changed execution policy; [SECURITY.md](SECURITY.md) keeps those
  human gates.
- **Critical threshold.** Confirm whether the proposed count includes only
  validated critical findings, or also non-review failures (provider outage,
  budget, Git drift). Choose a default `N` and whether it is project-wide or
  per-board; the proposal above uses a project-wide count and no silent reset.
- **Task intake.** Keep explicit human selection of agent proposals, or approve
  a narrowly scoped bulk-import policy. Do not silently turn arbitrary model
  text into trusted task commands.
- **Concurrency.** Expose a project cap in UI alongside the existing board cap.
  Confirm whether one saved agent may occupy multiple concurrent stage slots;
  provider quotas and real shared-login concurrency must be verified first.

## Small implementation slices and acceptance

1. **Configuration and preflight:** project cap, threshold, board role editing,
   explicit existing-board update, and a single readiness view. Test snapshot
   preservation, unsupported adapters, missing sign-in, dirty/unborn base,
   dependencies, keyboard access, and actionable errors.
2. **Durable project control and dispatch:** Start/Pause/Resume status and
   events; wire the existing admission planner to supervised, idempotent task
   preparation/start. Test two concurrent tasks, capacity release, fairness,
   duplicate clicks/ticks, restart/sleep reconciliation, and no cross-project
   process, port, credential, worktree, or knowledge leakage.
3. **Stop conditions and monitoring:** durable blocker count, threshold trip,
   safe pause, and a clear board/dashboard projection showing active,
   deferred, blocked, waiting, and completed work. Test count uniqueness,
   severity changes, retries, threshold edits, all-done detection, LiveView
   refresh, and recovery after a process crash.
4. **Completion policy (after decision):** either keep the human local-complete
   gate with honest **Needs attention** semantics, or add an explicitly
   approved local-only auto-complete policy with evidence checks, audit,
   security review, and an ADR. External release and merge remain human-owned.

Use the current SQLite event/command ledger, `ProjectWorkflow`, `GuidedRun`,
`Scheduler`, and LiveView surfaces. Do not add a second workflow engine or put
authoritative scheduling state in a GenServer. Real-provider and signed-app
acceptance remain separate from deterministic tests.
