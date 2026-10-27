# Dependency readiness UI — 2026-10-27

## Scope and baseline

- Isolated `codex/boss-dependency-ui`, baseline `40c6f1b`. Ownership: ProjectLive,
  RunPanel's new-start prop, new TaskDependencies component, focused LiveView tests,
  this log. Root owns backend and shared documentation. No provider calls.
- Reuse the existing drawer slot, native modality and async detail refresh. Disable
  new workflow/Codex starts on dependency blockers; preserve unknown UUID replay and
  already-admitted check/review/integration behavior.
- Dependencies describe the pinned task revision. Selecting/importing another
  revision does not adopt its declarations.

## Reference research

- Query: `rtk proxy xerj search --prefix bossrefs dependencyReasons -k 2 --full 1800`.
  Read `examples/backlog/packages/core/src/scheduler.ts:108-128` and
  `scheduler.test.ts:48-75`, pinned SHA
  `3580cfbbb1be4144a5cca5b49190e1f8158e4cf7`, Apache-2.0 (`LICENSE`).
- Adopt distinct waiting versus unknown/failed reasons and visible dependency
  state. Independently implemented Phoenix rendering; no source copied.
- Reject the broader scheduler/scoring/policy layer: this increment gates explicit
  starts and preserves the existing single-run admission and evidence contracts.

## Implementation and verification

- Compact escaped dependency list with same-project task links and saved revision
  context. New starts have a separate gate from retained check/review/integration.
- Dependency admission rejection is a known result that unlocks pending input and
  refreshes task details. Unknown starts retain original UUID/input for retry.
- Used a temporary `deps` symlink to the primary checkout solely for local tests;
  removed the symlink before branch handoff.
- Elixir/OTP verified: `.tool-versions` pins `1.20.3-otp-28`; `rtk proxy asdf exec
  elixir --version` reports Elixir1.20.3 / OTP28. First compile
  `rtk proxy asdf exec mix compile --warnings-as-errors` passed. Dependency compilation
  emitted an existing third-party deprecated `xref` configuration warning.
- Fast-forwarded the backend checkpoint `6616b8d` before integrated tests. No
  backend files changed by this writer.
- `rtk proxy asdf exec mix test test/boss_web/task_dependencies_live_test.exs
  test/boss_web/task_delivery_live_test.exs test/boss_web/task_run_live_test.exs
  test/boss_web/task_review_live_test.exs test/boss_web/task_board_live_test.exs`:
  43 passed, seed272341, 1.9s. Seven new cases cover waiting/Ready/Done refresh,
  same-project links, forged starts, pinned versus selected source, escaped unknown
  references, cycles, invalid declarations, missing/Done sources, stale admission,
  unknown UUID/input retry and retained checks/review controls.
- `rtk proxy asdf exec mix test test/boss_web/task_checks_live_test.exs
  test/boss_web/delivery_panel_test.exs`:13 passed, seed205503, 0.6s.
- Final `rtk proxy asdf exec mix compile --warnings-as-errors`, focused
  `mix format --check-formatted` and `rtk proxy git diff --check` passed.
- Outcome: dependency readiness is visible and prevents new starts in UI and event
  handlers, while pending request reconciliation remains available. Existing
  native drawer/URL selection/Stop/coalesced refresh behavior is unchanged.
- No real provider calls, Git publication or browser checks in this writer task.
  Next: root review/merge, combined verification and browser smoke; root owns
  AGENTS/shared documentation and local-main cleanup.
