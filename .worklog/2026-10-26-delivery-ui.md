# Managed delivery UI increment

- Scope: isolated `codex/boss-delivery-ui` from `17c2bc3`; new workflow panel,
  ProjectLive request handling and focused UI tests. Parent owns persistence,
  shared documentation/task files and final main integration.
- Skills: RTK, Ponytail and frontend-ui-engineering. Use existing Phoenix/HEEx
  styles and escaped text, without dependencies or raw output persistence.
- Reference query: `rtk proxy xerj search --prefix bossrefs 'idempotency commandId' -k 2 --full 1200`
  returned weak lexical matches; followed with direct source inspection.
  Read `examples/backlog/packages/core/src/retry.ts:40-61` and
  `retry.test.ts:20-95`, pinned `3580cfbbb1be4144a5cca5b49190e1f8158e4cf7`,
  Apache-2.0. Adopt explicit cycle budget/feedback visibility; reject retrying
  every failure generically. No reference code copied.
- Decisions: managed workflows have a separate explicit trusted-command form;
  old manual review reports cannot offer integration. Persisted delivery receipts
  resolve unknown admissions. Request keys include task/action/target/UUID so a
  late response cannot replace a newer request. Unknown inputs remain locked,
  including across drawer navigation. Stop routes directly through the context.
  Ready to integrate and Done are separate persisted states. Board refresh shares
  existing coalesced notifications, with details read under one Repo transaction.
- Discovered and fixed a navigation/read race: cancelling a details task inside
  its deferred Repo transaction could leave the next selection with storage_error.
  Keep one details read, discard obsolete selections and then read the latest
  desired selection; closing the drawer never owns delivery execution. Updated
  the existing task-board regression to assert the old read stays alive while its
  source is hidden. Run notifications now also preserve pending interrupted sync.
- New real-context UI fixture caught a backend command collision between Ready
  and Done (same complete event ID). Parent fixed it in `6d12007`; the UI test
  retains the complete plan/check/review/publication/post-check receipt chain.
- Finished files: `delivery_panel.ex`, `project_live.ex`, new component/workflow
  LiveView tests and the focused navigation assertion in `task_board_live_test.exs`.
- Verification on parent context checkpoint `6d12007`:
  `rtk proxy asdf exec mix test test/boss_web/delivery_panel_test.exs test/boss_web/task_delivery_live_test.exs test/boss_web/task_run_live_test.exs test/boss_web/task_checks_live_test.exs test/boss_web/task_review_live_test.exs test/boss_web/project_live_test.exs test/boss_web/task_board_live_test.exs test/boss_web/spec_sync_live_test.exs`
  passed 65 tests, seed 73819. Includes explicit cost/command text, active Stop,
  saved Ready/Done separation, target SHA, escaped review, identical UUID retry,
  late-result ordering, scope isolation, invalid-command recovery, manual/managed
  exclusion and board updates after persisted Done. All execution is finite fake
  workers; no real provider CLI was called.
- Review: used code-review-and-quality; changed the component integration guard
  from ready_to_merge to done as a temporary mutation. Component suite failed the
  Ready and Done cases (2 failures, seed 935676), then the original file was restored
  and byte-hash checked. Restored component suite passed 6 tests (seed 721088).
  Focused format check and `rtk proxy git diff --check` passed. No copied
  reference source or additional dependency.
- Compilation currently warns about Worker/Integration modules not yet merged from
  the other isolated branches; combined warnings-as-errors/full-suite/assets and
  real-browser checks belong to parent integration. No paid live smoke run.
- Outcome: UI ready for parent review/merge. Next: merge the UI commit after worker
  branches, run combined checks and browser inspection, then remove this temporary
  worktree/branch. Parent owns AGENTS/task/shared-documentation updates.


## Combined UI review follow-up

- Reviewed combined root `3bcb9fb` read-only: request replay/late replies, task
  selection, manual/managed exclusion, native dialog hook and explicit integration.
  Found one actionable race: a Stop arriving after the worker's final cancellation
  checkpoint can leave Ready with `delivery_stopping` still set. Integration reuses
  that delivery ID, so its Stop button remained disabled.
- Parent authorized a narrow fix. Refresh now clears the Stop indicator only when
  the matching persisted delivery is no longer active. Regression drives real
  LiveView Start → late Stop → persisted Ready → Integrate → enabled Stop using
  finite fake workers. It failed before the fix (seed 224756, `stop_enabled` false).
- Extended persisted-Done UI regression to open a different task and explicitly
  start its workflow, confirming old request/phase locks no longer prevent work.
- The same eight-file UI test command above passed 66 tests, seed 625165. All
  production workers were merged for this run; no provider invocation.
- Reviewed `assets/js/app.js`/TaskBoard dialog: native showModal, preserved `open`,
  focused revision synchronization and return focus to the moved task card remain
  intact in source. Browser validation remains parent-owned, not inferred.
- Browser fixture recommendation uses existing `test/fixtures/codex_delivery.py`
  and `delivery_check.py`, following `delivery_worker_test.exs` setup. Earlier
  scratch startup scripts were removed per the parent worklog; avoid blocking
  token FIFO (previous fixture blocked Erlang file service). Use an exclusively
  created root, fixture CLI first in PATH, local check argv, and free target main.
- Follow-up `mix compile --warnings-as-errors`, focused format check and
  `git diff --check` passed. Temporary deps symlink removed before commit.
