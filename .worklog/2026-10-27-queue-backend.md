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

Final focused verification:
- Queue context + real-pool lifecycle suites: 15 passed after UUID guard and
  scheduling index changes.
- `rtk proxy asdf exec mix test test/boss/run_persistence_test.exs
  test/boss/check_persistence_test.exs test/boss/review_persistence_test.exs`:
  19 passed in 60.8 seconds, including production transport running status before
  Stop. No paid providers.
- `rtk proxy asdf exec mix format --check-formatted`: passed.
- `rtk proxy git diff --check`: passed.
- Both reference checkout HEADs verified against pinned manifest SHAs.

Queue has an index on status/inserted_at/id so a 32-row pending sweep does not scan
unbounded immutable terminal history. No speculative file-overlap prediction,
automatic integration or settings/dependency changes were added.

Outcome: broad `rtk proxy asdf exec mix test test/boss` completed with **357 passed,
1 skipped** in 507.9 seconds. It began at foundation d07b674 before the seven new
persistence tests were created; final queue behavior is additionally verified by
the separate 15-test queue suite after the later UUID guard/index changes. The
native process suites remained finite fake CLIs. Parent reruns combined UI/native
acceptance and full suite against integrated final source.

Final next step: merge backend commits through final worklog commit into the parent
integration branch, review combined UI/native evidence, then parent merges local
main and removes temporary branches/worktrees. The owned dependency symlink was
removed after tests; no reference checkout or shared documentation was modified.

Combined-suite follow-up: root seed 276199 exposed a web sandbox fixture leak: an
application-global Manager timer queried after its SQL Sandbox owner ended, causing
restart-intensity failure. Backend caller audit (`rtk proxy rg` for Manager,
Queue.enqueue/resume and Runs/Deliveries.start under test/boss) found only isolated
start_supervised Managers with dedicated real pools; backend DataCase queue tests
use direct admission/claim helpers and never arm a timer. No backend test or
production exception handler change is warranted. UI writer owns clearing/draining
its global Manager timers before sandbox teardown. Suggested deterministic check:
retain an old timer tag, reset fixture while owner is alive, deliver the stale tick,
and verify same Manager PID/no timer/no active or finished owners. Combined rerun
remains parent-owned; no new passing result is claimed for that failing seed here.
