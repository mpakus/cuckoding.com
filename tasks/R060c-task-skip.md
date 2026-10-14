# R060c — Skip a task and retain partial results

Status: completed, 2026-10-14. Branch: `feature/R060c-task-skip`.

- [x] New Start snapshots explicitly permit skipping the current unintegrated task
  at a clean paused boundary or settled task-local provider/review failure.
- [x] Confirm the exact task/control revision, atomically defer its transitive
  dependents, preserve drafts, attempts, edits, reviewed head and original budgets.
  Reject historical grants, stale controls, active/uncertain workers and policy drift.
- [x] Continue independent tasks from the reviewed head. Final checks/review cover
  the retained subset with explicit omissions; report Partial, never Completed.
  Stop without inference when all tasks were omitted. Paused battles stay paused.
- [x] Add accessible Arena confirmation and task statuses; preserve Agents/Team.
  Cover domain, executor and LiveView regression scenarios including restart.
- [x] Update docs/AGENTS/README, run quality/build/smoke, preserve and relaunch the
  saved workspace, commit and merge local main. No live provider inference or push.

Evidence: [worklog](../worklog/2026-10-14-R060c-task-skip.md).
