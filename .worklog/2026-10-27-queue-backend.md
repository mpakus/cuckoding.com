# BOSS-015b queue backend — 2026-10-27

Baseline: `51c0967`, isolated `codex/boss-workflow-queue`.
Scope: durable explicit queue, two managed workers, exclusive manual/integration,
SQL invariants and bounded recovery. Parent owns shared docs and native acceptance;
UI writer owns web code/tests. No provider calls or dependencies.

Reference coding: `rtk proxy xerj search --prefix bossrefs pendingDispatches -k 3 --full 1200`
returned no match; read source directly as required. Backlog
`examples/backlog/packages/core/src/orchestrator-loop.ts:372-398`, SHA
`3580cfbbb1be4144a5cca5b49190e1f8158e4cf7`, Apache-2.0: adopt explicit restart
pause because automatic hydration previously launched stale work. Independently
implemented; reject autonomous resume and a general scheduler framework. Queue
request UUID and immutable inputs follow existing BOSS delivery receipts.

Foundation implements UUID queue receipts, shared atomic delivery admission, immutable SQL
queue guards, two managed slots and exact-id/PID worker completion. UI uses config_hash
and Queue.pause/0 for persisted restart fixtures. Existing active-map callers adjusted.

Verification so far: `rtk proxy asdf exec mix test test/boss/deliveries_test.exs
test/boss/delivery_reviewer_persistence_test.exs` — 14 passed. New queue focused
suite initially found one assertion using the wrong existing dependency error name;
corrected to dependencies_blocked. Re-running before foundation handoff.

Review found worker completion messages could release a slot before process death;
Manager now retains finished receipts until the matching worker EXIT. Real pool
concurrency/restart and lifecycle regression coverage still in progress.

