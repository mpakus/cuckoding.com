# R070d — Bounded independent task waves

Status: verified implementation, 2026-10-21; local main integration recorded in the worklog.

- [x] Freeze a new two-lane wave policy in new Starts; keep old Starts sequential.
  Claim only independent ready tasks; use separate attempts/worktrees/sessions,
  the two-worker global cap and one provider turn per exact connection.
- [x] Run preparation/coordinator/Speculator/Implementor/capture concurrently where
  bindings permit. Wait for the wave before serialized check/review/integration.
  A changed head requires R070b combination and fresh independent review; conflicts
  return through bounded fresh-worktree Speculator/Implementor repair.
- [x] SQLite owns each task stage and claim. Migrate only claim indexes forward;
  preserve prior data and all immutable attempts. Keep native repository I/O
  serialized/cancellable without using a VM lock as effect/cleanup authority.
- [x] Pause drains all bounded stages; Stop cancels all and waits for exact cleanup.
  Failed waves drain before attention; explicit Retry/Skip retain per-task limits,
  all failed evidence and the original deadline. Preserve legacy controls.
- [x] Restart/timing fences retain every interrupted attempt; never infer closure
  from process absence or replay. Keep provider/integration inspection bound to
  the exact attempt and frozen scope.
- [x] Update simple Start/Inspect/worker copy through existing LiveView components;
  no second Start, mandatory setup or silent binding changes.
- [x] Prove two independent tasks plus a dependent third, same-connection queue,
  combined review/conflict repair, concurrent claims, budgets/controls/crashes and
  old snapshots. Prior-schema copy, host/native/packaged checks, docs/AGENTS/README
  and local main merge. Real-provider concurrency remains separate acceptance.

Scope: different saved responsibility bindings may overlap provider turns; one
role's exact connection remains serialized. Explicit additional simultaneous
writer/role slots remain required R030/R070 work, as do real-account acceptance
and the broader beta gates. This slice does not complete the full beta goal.

Evidence: 480 Mix tests and full quality passed; prior-schema/claim preservation,
readiness mutation, desktop/320px browser scope and keyboard disclosure, source
smoke, strict/deep ad-hoc signature and packaged smoke passed. See the worklog
for exact commands, retained data and limits. No real provider turn was launched.
