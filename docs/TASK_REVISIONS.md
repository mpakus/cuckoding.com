# Explicit task source revision adoption

Import preserves every source revision and leaves the task snapshot unchanged.
In the task drawer, select a newer saved revision, inspect its source, then choose
**Use revision N**. Viewing a revision alone never changes the task.

Adoption changes the task's pinned source, title and dependency declaration,
resets its state to New, clears the previous attention/recovery state and advances
its task version once. It does not edit Markdown files or start an agent.
A target must belong to the same spec and have a higher revision number than the
current snapshot. A newer saved revision may be selected even when a later one
exists; older/current revisions cannot be adopted.

## History and approval

Original sources, plans, workspaces, runs, checks, reviews and task events remain
retained. The adoption event records both the previous and target source revision.
An unintegrated Ready approval is retired in the same transaction, so its reviewed
commit cannot authorize the new source. New workflows start from the project's
base with the adopted requirements and fresh evidence.

Historical manual checks and reviews continue to use their parent's saved source
and candidate commit. Their receipts remain advisory; they do not approve the
new revision. Each saved run/workflow shows the revision to which it belongs.

## Admission and retry

Adoption uses `Boss.Tasks.transition/2` with `action: "adopt_revision"`, explicit
`project_id` and `spec_revision_id`, `expected_version` and a task-scoped
`command_id`. The event, task update and retirement of a Ready delivery share one
immediate Repo-pinned transaction. The target's saved Markdown is validated again;
its identity must match the spec. Caller-provided source or title is not accepted.

An identical command returns its original immutable event before checking current
eligibility. Changing target/version with the same ID is a conflict. A foreign project is
rejected as not found before exposing task history.
Unknown storage outcomes must be retried with the original complete command;
the drawer retains that command while the user navigates between revisions.

Only idle New, Ready, failed, interrupted, cancelled, blocked, needs-input and
Ready-to-merge tasks are eligible. Done remains closed because other tasks may
already depend on its integration evidence. Full persisted history, including
records outside the visible recent list, is checked for active or unknown runs
and workflows. A queued or paused workflow request also blocks adoption; cancel
that request before accepting a new source. An unfinished integration intent also
blocks adoption: publication or retained target work may need reconciliation even
after an execution stopped.
Changing the source cannot clear those conditions. Unrelated task activity does
not prevent this metadata operation.

A syntactically valid target may still have waiting, missing or cyclic dependencies.
Adoption does not execute it; [dependency readiness](TASK_DEPENDENCIES.md) gates
the next Start. This permits repairing declarations one task at a time.

Committed adoption refreshes the board, source snapshot and dependency status in
connected drawers. Publication occurs after a top-level transaction returns;
a nested caller must publish only after its outer transaction commits.

## Migration and verification boundary

The migration retains existing task events and execution history, adds the target
revision to adoption receipts, and preserves historical check/review parent pins.
Restart BOSS after updating so startup applies migrations before serving requests.
No migration rewrites saved requirements, credentials or workspaces.

Verification results and cleanup status are recorded in `.worklog/2026-10-27.md`.
Provider acceptance, automatic scheduling, reopening Done and resolution of
unknown cleanup or incomplete integration remain separate work.
