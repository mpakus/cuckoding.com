# Task 1030 worklog — Ready-task admission feedback

Acceptance: the board explains why each Ready task has not started under project automatic mode, including dependency, capacity, paused control, and queued run; manual access remains available. No second scheduling state is stored.

Initial state: clean `main` tracking `origin/main`. Task 1029 is complete; the board still says Ready tasks never start automatically while the project dispatcher now does. Reuse `Scheduler.plan/1` read-only output and its existing deferral reasons. The only shared boundary change is a read-only planner wrapper for the project control limit.

Reference coding: existing `Cuckoding.Execution.Scheduler.plan/1` and `BoardLive` are the direct project precedent; no unfamiliar external API is introduced.

Implementation: `ProjectAutopilot.admission_plan/2` reads the scheduler's candidate and deferred decisions with the project's durable limit. The board maps those reasons to public copy and refreshes the board projection after committed activity events, including a pause from another browser. No task or admission state was added.

Verification:

- `rtk mix test test/cuckoding_web/board_live_test.exs test/cuckoding/project_workflow_test.exs` — 21 tests, 0 failures.
- `rtk mix test test/cuckoding_web/board_live_test.exs` after the cross-browser board-status fix — 7 tests, 0 failures.
- `rtk mix format lib/cuckoding/project_autopilot.ex lib/cuckoding_web/live/board_live.ex test/cuckoding/project_workflow_test.exs test/cuckoding_web/board_live_test.exs` — passed.
- `rtk mix quality` after the final change — 299 tests, 10 properties, 0 failures; Credo found no issues; Sobelow scan and Hex audit passed. The logged fixture crashes are expected by the plugin supervisor test.
- `rtk mix assets.build` — passed (Tailwind and esbuild).
- `rtk git diff --check` — passed.

`rtk proxy` was used for exact, unfiltered source and Git metadata reads where RTK's summarized output would hide lines; no repository mutation was run through that exception. Signed-build and real-provider gates are unchanged.

Review follow-up: `review-agent` reproduced two defects in commit `4f1bdfe`: selected scheduler candidates expose `task.id` rather than `task_id`, and a prepared queued run does not populate `tasks.active_run_id`. Reopened task 1030 to fix both paths and add the missing regression coverage.

Follow-up implementation: selected candidates now use their nested durable task ID. The board loads queued runs for all displayed board tasks in one query, uses that projection for the prepared status and run link, and still prefers an active run once execution owns the task.

Follow-up verification:

- `rtk mix test test/cuckoding_web/board_live_test.exs test/cuckoding/project_workflow_test.exs` — 22 tests, 0 failures. New cases cover an eligible scheduler candidate plus queued-run status and navigation.
- `rtk mix quality` — 300 tests, 10 properties, 0 failures; Credo found no issues; Sobelow and Hex audit passed. The logged plugin-worker crashes are intentional test fixtures.
- `rtk git diff --check` — passed.

Ponytail upstream 4.10.0, MIT license, stayed in full mode. The fix reuses the existing execution context and adds no dependency or durable scheduling state.
