---
status: done
owner: codex
started_at: 2026-09-19
completed_at: 2026-09-19
worklog: worklog/2026-09-19-1010-planning-run-live-feedback.md
---

# 1010 — Planning-run LiveView feedback

## Goal

Make planning-run creation visibly responsive and show durable, real-time progress through authentication, analysis, and proposal review.

## Acceptance criteria

- [x] Submitting the board form immediately disables and relabels the action while work is pending.
- [x] Successful creation navigates to the run and announces what happened and what to do next.
- [x] The run page shows planning progress derived from durable run state.
- [x] PubSub activity refreshes planning progress without a page reload.
- [x] Errors remain adjacent, accessible, and actionable.
- [x] Focused LiveView tests and project quality gates pass.

## Verification

- `rtk mix format --check-formatted`
- `rtk mix compile --warnings-as-errors`
- `rtk mix test test/cuckoding/board_task_intake_test.exs test/cuckoding_web/board_live_test.exs`
- `rtk mix credo --strict`
- `rtk mix sobelow --config`
- Browser smoke test on the running development server
- `rtk git diff --check`
