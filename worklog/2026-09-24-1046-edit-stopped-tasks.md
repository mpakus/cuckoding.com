# 1046 — Edit task details after a stopped run

Acceptance: edit stopped delivery tasks safely, preserve previous evidence,
save before retry, retain entered text, explain the existing Speculator retry
path, and verify domain/UI/audit behavior plus the rebuilt app.

Started from clean main at f4014cb; branch feature/1046-edit-stopped-tasks.
Applied Ponytail 4.10.0 full (MIT), workflow-and-kanban, LiveView, security review
and quality gates. Existing Workflows.update_task and TaskLive both only permit
Draft/Ready. Inspecting saved inputs and retry semantics before changing this
shared boundary. `rtk proxy` exceptions: exact source/SQLite reads and test/build
diagnostics. No native task content or run state will be changed for a test.

Read-only inspection of the supplied native task: Blocked, latest run Blocked,
all five recorded processes exited. Authenticated Chrome confirmed the obsolete
Draft/Ready-only message. Existing source references used: contexts.ex
Workflows.update_task/edit_task; ProjectWorkflow.retry_task (stopped-run/process
checks); EventStore.transaction (immediate SQLite transaction and after-commit
broadcast); WalkingSkeleton.role_objective (saved description reaches the
planning/implementation/review stages). This is an extension of those existing
paths; no new agent workflow, provider call, dependencies, tables or grants.

The shared Workflows.task_editable? predicate now includes stopped delivery
tasks with a matching latest run and no running process. Saving rechecks under
the existing EventStore transaction. Task input has separate LiveView draft
assigns, survives validation/activity refresh, and remains visible if editing is
subsequently locked. Retry now uses the existing unsaved-change guard. Existing
agent assistance is the assigned Speculator stage on the new retry; the UI
explains this without claiming a standalone agent editor. Historical run data
is not rewritten; task edit events record changed field names and task state.

Focused validation: `rtk env -u CR_PAT mix format` and
`rtk env -u CR_PAT mix test test/cuckoding_web/board_live_test.exs test/cuckoding/project_workflow_test.exs`
passed: 28 tests, 0 failures. An initial run exposed one obsolete copy assertion;
updated to the new eligibility guidance. Regressions cover blocked/failed/
cancelled edits, live-process and stale-browser rejection, unsaved retry guard,
draft/error preservation, previous-run event/snapshot equality, saved input
loaded by the new retry, and server-side length/priority validation.

`rtk env -u CR_PAT mix quality` passed: format, unused-dependency check,
warnings-as-errors compilation, 10 properties / 351 tests, strict Credo,
Sobelow and Hex audit. This includes transition property, scheduler fairness,
LiveView keyboard and secret/confinement coverage. No findings/advisories.
