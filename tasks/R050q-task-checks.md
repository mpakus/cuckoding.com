# R050q — Planned task checks through one Start

Status: implemented and verified, base `9abfde1`, 2026-10-24; local integration only.

- [x] Version new planning as brief-plan-v4. Propose zero to four fixed npm-test /
  mix-test profiles per task, with bounded relative directory and timeout. Preserve
  old contracts and exact provider/no-tools bindings; reject downgrade/unknown input.
- [x] Store profiles in immutable task revisions, import atomically, preserve
  omitted legacy fields and accepted-spec bytes. Inspect/edit them inside the
  existing task dialog; retain dirty forms, guards and active battle locks.
- [x] One Start freezes host-resolved profiles and bounded guest grant, without
  Advanced setup. Run each task's checks, integrated work and explicit Arena checks; final
  checks cover the retained tasks and all configured checks. Preserve review,
  correction, Skip/Partial, wave/combined checks, budgets, cleanup and old snapshots.
- [x] Add forward-only schema/backup/old-bundle fence and focused/native/LiveView
  regressions. Prove generated cards through the actual OTP/native VM loop with
  synthetic providers only; update docs/AGENTS/README and merge local main, no push.

Failure-output delivery, dependency provisioning/platform equivalence, keeper-loss
recovery, real-provider and release acceptance remain required beta work. This
slice removes manual check configuration from generated-task execution; profile
proposals are data until explicit bounded Start, never runtime shell permission.

[Implementation and verification evidence](../worklog/2026-10-24-R050q-task-checks.md).
