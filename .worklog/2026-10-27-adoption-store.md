# Explicit revision adoption — storage implementation

- Baseline main680503c, isolated codex/boss-adoption-store. Scope: Tasks command/
  read contract, Revisions policy, immutable Event target, two additive migrations,
  affected migration fixtures and backend tests. Root owns shared documentation.
- Reference research supplied by parent/read-only agent: xerj bossrefs query
  `Expect rejects stale revisions`, Kander internal/board/transaction.go:214 and
  transaction_test.go:432 at dea0ba6b885c39a56ee769223f7fa5c054e68c70 (MIT).
  Adopt transactional expected-version checks; preserve history, reject stale
  writes. Reject filesystem journaling and batch/role machinery; no code copied.
- Explicit adopt_revision command pins project and target revision, retains old
  spec_revision_id plus target_spec_revision_id in the same immutable event.
  Task version, title, source, New state and cleared attention/recovery update
  atomically; Ready approval retires in the same transaction.
- Task-scoped full persisted active/unknown work and unresolved integration intent
  block adoption; Done and active workflow states stay closed. Target must be a
  newer same-spec saved source whose parsed identity/title are valid. Readiness
  itself is not required, permitting staged dependency repairs.
- Task details return selected revision adoption availability and revision IDs.
  Tasks.subscribe/1 receives {:task_changed, project_id} only after successful
  top-level transaction return; nested caller must broadcast/1 after outer commit.
- Historical manual checks/reviews retain parent source after adoption. Separate
  pin migration keeps current revision for new Codex and existing parent provenance
  checks for check/review. Downgrade refuses adoption or mismatched historical
  verification; receipt-column downgrade refuses retained task events.
- First focused pass found two incorrect test expectations: retired integration
  returns existing :not_ready; completed delivery return can precede refreshed
  task_version, so command test reads current task version. Fixed tests only.
- `rtk proxy asdf exec mix test test/boss/revision_adoption_test.exs
  test/boss/revision_adoption_persistence_test.exs test/boss/task_details_test.exs
  test/boss/tasks_test.exs test/boss/deliveries_test.exs test/boss/reviews_test.exs
  test/boss/spec_persistence_test.exs`:60 passed,seed836480,1.0s. Includes exclusive
  scratch SQLite pool concurrency/admission race, restart replay, postcommit and
  nested rollback notification, and migration protection. One unused test binding
  warning was then removed. No provider calls or UI/browser verification here.

## Final focused verification

- Intentional mutation changed the manual active-owner task predicate from == to
  !=. The active/unknown adoption refusal test failed by accepting adoption
  (seed747547,exit2). An initial line148 command selected the adjacent unrelated
  test and stayed green; corrected location137 exercised the intended regression.
  Restored exact original source SHA256
  265c960b2c3fee5ce65d6117e09f106ae8b28ca673c117f37ad00490b27ec5c6.
- Added real-pool competing different-target CAS regression and direct SQL pin
  regression: historical check/review remains valid, new Codex cannot use the
  pre-adoption source, and normal current-revision admission still succeeds.
- Final seven-file suite above:61 passed,seed362045,1.0s; no warnings. Dev compile
  --warnings-as-errors, format --check-formatted and git diff --check passed.
- Writer scope complete. Parent owns integration/full suite/browser/docs/main.
  No provider calls, recovery UI, reopening Done or scheduler were added.
