# R060r — Continue independent work around verified task blockers

Status: implemented, verified, packaged and merged locally, 2026-10-23. Base `c4f43f6`.

- [x] Freeze a new policy in new Starts only. Classify exact validated provider
  `blocked` and exhausted task Secutor review as task-local after verified cleanup;
  native/policy/auth/transport/budget/timing/uncertain failures remain Arena-wide.
- [x] Drain current workers first, retain the blocked task/receipt and continue
  only independent ready tasks from the reviewed head. Dependents stay pending;
  unresolved tasks never reach final review/Completed or implicit Skip.
- [x] Preserve Pause, Stop, restart checkpoints, exact bindings, capacity,
  deadlines/retries and separate blocker decisions. Prioritize Arena-wide attention.
- [x] Protect old bundles with a backed-up forward-only compatibility migration
  and a DB guard against claiming a blocked task; keep historical policies unchanged.
- [x] Show compact task/Arena attention in LiveView, verify adversarial domain,
  OTP/control/UI/migration regressions and build/smoke; update docs/AGENTS/README,
  merge locally and remove the feature branch without publishing.

[Verification and artifact](../worklog/2026-10-23-R060r-task-local-blockers.md).
Implementation `e6c178a`, LiveView `0f7d898`, evidence `2b3bd00` are on local main.
