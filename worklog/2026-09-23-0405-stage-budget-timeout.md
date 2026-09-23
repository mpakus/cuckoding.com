# Worklog — 0405 stage budget timeout regression

## Metadata

- Date/time (UTC): 2026-09-23 04:16
- Task: 0405 Walking Skeleton follow-up; claim limited to stage wall timeout
- Status: review
- Owner: Codex
- Branch: `fix/0405-stage-budget-timeout`
- Start revision: `a116fc6`
- Ponytail: upstream 4.10.0, MIT, full mode

## Intended outcome

- A delivery agent receives the immutable run snapshot's wall-time budget for its stage, rather than an unrelated five-minute limit.
- A focused test fails if the Coding stage ignores a non-default snapshotted budget.
- Preserve prior run/worktree evidence and do not automatically retry a partially written task.

## Context and cause

- Echo task `01a0bb7c-f6d7-72de-9f92-7592e7cc3dc4`, run 2 `01a0cc65-6e30-7674-b71a-9d91424debbe`: Specifications succeeded. Coding started at 03:54:58 UTC, `process.timeout` occurred at 03:59:58 UTC, and the process exited 130 after Cuckoding sent INT. The run then became blocked.
- Its immutable workflow snapshot sets the Coding stage `wall_ms` to `3600000`; `WalkingSkeleton.request/4` instead granted `300000` to every stage. The runner enforced that shorter grant.
- The redacted agent log shows active Phoenix generation and dependency verification before the timeout. The run worktree retains untracked generated application and vendor files. No retry or cleanup was performed.
- Local source and `docs/REFERENCE_CODING.md` were inspected. This is a direct mismatch between two existing Cuckoding values, so no peer code or new abstraction was needed.

## Work performed

- `WalkingSkeleton.request/4` now reads the stage wall limit from the run's saved workflow definition.
- Reused the existing capturing adapter to check a Coding request against a non-default test snapshot.
- No credentials, paths, network grant, approval gate, or process-ownership behavior changed. The existing bounded adapter validation still rejects invalid wall limits. Historical events remain immutable.
- `docs/FLOW.md` already specifies snapshotted stage budgets; no public documentation claim changed.

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| `rtk mix test test/cuckoding/walking_skeleton_test.exs:964` | initially unavailable | Isolated worktree had no fetched Mix dependencies. |
| `rtk mix deps.get` | pass | Pinned dependencies resolved. |
| `rtk mix test test/cuckoding/walking_skeleton_test.exs:964` | pass | 1 focused test after custom snapshot assertion. |
| `rtk mix test test/cuckoding/walking_skeleton_test.exs` | pass | 24 tests, 0 failures after the custom snapshot refinement. |
| `rtk mix test test/cuckoding/adapters/cursor_agent_test.exs` | pass | 8 tests, 0 failures; confirms the adapter's existing timeout mapping. |
| `rtk mix format --check-formatted` | pass | After final test edit. |
| `rtk mix compile --warnings-as-errors` | pass | Warning-free compilation. |
| `rtk mix credo --strict` | pass | No issues. |
| `rtk mix test test/cuckoding/workflows/definition_test.exs test/cuckoding/execution/scheduler_test.exs test/cuckoding_web/board_live_test.exs` | pass | 2 properties, 18 tests, 0 failures. |

## Risks and handoff

- The already-blocked run is historical; this code change does not retroactively uninterrupt it or copy its partial work to a new run.
- The currently running local Cuckoding server uses another checkout. Deploy/restart this code before retrying, and review the preserved Echo worktree first; the app's normal retry creates a fresh worktree and does not carry uncommitted files.
- No release, packaging, or real-provider end-to-end run was performed in this isolated fix checkout.

## Checklist

- [x] Acceptance criteria reviewed.
- [x] Relevant documentation checked for drift.
- [x] Focused and proportionate checks recorded.
- [x] Secrets and sensitive content excluded.
- [x] Residual operational risk and next step explicit.
