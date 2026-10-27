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


Second reference: Kander `examples/kander/internal/board/dispatch.go:234-260`,
SHA `dea0ba6b885c39a56ee769223f7fa5c054e68c70`, MIT. Existing immutable intent
replay precedes current evidence/readiness validation. Adopted the ordering and
rejected filesystem registry/state replication; SQLite already owns BOSS admission.
No source copied.

Frozen foundation review (`d07b674`) corrected two lifecycle risks: terminal
message keeps owner/ETS until actual EXIT; run progress carries explicit worker
owner independently from the process transport's consumer callback. A follow-up
review fixed cancelled/stale queue UUID reuse through direct Start at context and
SQL boundaries.

`rtk proxy asdf exec mix test test/boss/workflow_queue_test.exs
test/boss/workflow_queue_persistence_test.exs` — 15 passed. Includes real two-
connection SQLite duplicate enqueue/claim races, claim-versus-cancel, committed
restart, two-slot contention, explicit resume, late/wrong-PID completion, ownership
until EXIT, adoption API/SQL guard and downgrade refusal. The first adoption test
used the wrong command key (type rather than action); corrected fixture and reran.

Full backend and finite production run/check/review regression suites running.
No live model calls; provider quota, file-scope prediction and divergent integration
remain outside this backend increment. Parent owns actual native two-worker smoke,
combined review/full suite and local main cleanup.
