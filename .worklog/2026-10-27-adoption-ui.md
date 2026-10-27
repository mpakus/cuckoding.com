# Revision adoption UI — 2026-10-27

- Baseline680503c, isolated codex/boss-adoption-ui. Own ProjectLive, TaskBoard,
  focused TaskRevision component, UI tests and this worklog. Shared docs/backend
  owned by root/store. Applied Ponytail and RTK.
- Research: xerj bossrefs query `Expect rejects stale revisions`, read Kander
  internal/board/transaction.go:214 and transaction_test.go:432. Pinned SHA
  dea0ba6b885c39a56ee769223f7fa5c054e68c70, MIT. Adopt explicit expected-version
  guard and fixed-target retry. Reject filesystem journal/role machinery; use
  existing SQLite receipts. No reference code copied or executed.
- Scope: view-selected source remains read-only; explicit Use revision N submits
  immutable target/version/UUID, pending unknown outcome retries original request,
  controls avoid races, committed events refresh other drawers. Native dialog/URL
  behavior preserved. Backend checkpoint needed before runtime verification.

## UI implementation and focused verification

- Integrated backend6ec16a3. Added TaskRevision panel/request helpers, explicit
  source action, unknown fixed-target retry and controls gated during unresolved
  adoption. Subscribed Tasks postcommit events; adoption receipt old/new source
  numbers appear in history. Per-run/delivery labels distinguish historical source.
- Seven new LiveView tests cover view/adopt separation, title/dependency reset,
  cross-view refresh, active/Done/unknown gates, stale refusal, forged IDs/selection,
  unknown original request across revision navigation and historical manual results.
- `rtk proxy asdf exec mix test test/boss_web/task_revision_adoption_live_test.exs
  test/boss_web/task_dependencies_live_test.exs test/boss_web/delivery_panel_test.exs`:
 20 passed, seed760086,0.6s. An initial test-only attempt to kill a borrower paused
  inside the sandbox invalidated its shared test connection; replaced with the
  existing controlled LiveView async pattern (dispatch lost before storage).
  Production code was not changed to accommodate the harness.
- No paid/provider/browser calls. Root owns browser proof, docs and main merge.
  Additional existing UI suites and final clean handoff follow.

- Existing task_run_live/task_review_live/task_board_live/task_checks_live/
  task_delivery_live/spec_sync_live suites:55 passed,seed888390,2.6s.
  `rtk proxy asdf exec mix compile --warnings-as-errors`, owned-file
  `mix format --check-formatted` and `git diff --check` passed. Total focused
  UI/component evidence:75 passed across the two commands above.
- Outcome: UI checkpoint7e99a9d ready for root integration/browser testing.
  No provider calls or remote publication. Temporary own deps symlink removed
  after all commands; source and test files are committed. Root owns final
  main merge/verification and managed worktree cleanup.
