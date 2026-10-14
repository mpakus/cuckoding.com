# R060b — Bounded provider retry

Status: completed, 2026-10-14. Branch: `feature/R060b-provider-retry`.

Continue recovery with an explicit Retry for settled transient provider failures.
Skip, uncertain-effect reconciliation and parallel scheduling remain separate.

- [x] Freeze `provider-retry-v1` and two retries per task (two shared by final
  stages) in new Start snapshots; historical battles do not gain retry authority.
- [x] Retry only normalized transient provider failures with verified cleanup.
  Refuse policy/model drift, blocked/rejected reviews, native-stage failures,
  interrupted attempts, stale controls, changed bindings and exhausted limits.
- [x] Preserve immutable attempts, failed tool/edit evidence, task criteria,
  review rounds, consumed turns, deadlines and reviewed Git head. A failed writer
  returns through a fresh worktree/coordinator/Speculator, never reusing partial edits.
- [x] Reuse session/revision guards, show one accessible Retry control with scope
  and usage explanation; preserve Pause/Resume after retry and Stop semantics.
- [x] Add domain/executor/LiveView concurrency, restart and adversarial regression
  checks; update docs, AGENTS and README; build/smoke, preserve the saved workspace,
  commit and merge local main without publishing or live inference.

Evidence: [worklog](../worklog/2026-10-14-R060b-provider-retry.md).
