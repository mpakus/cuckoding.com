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
