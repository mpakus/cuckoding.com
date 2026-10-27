# BOSS-016b integration evidence

Baseline408ca8a, isolated codex/boss-integration-evidence. Scope: immutable merge /
merge_check / merge_review stages, fresh reviewer evidence, exact current-target
publication and context/SQL regression tests. Root owns merge Git candidate helper,
shared docs and combined native/full verification; UI writer owns presentation.

Reference lookup: `rtk proxy xerj search --prefix bossrefs verifyClosureHead -k 2
--full 1200`; read Kander internal/review/disposition.go:196-225,
SHAdea0ba6b885c39a56ee769223f7fa5c054e68c70, MIT. Adopt exact clean final commit
verification. Reject reusing an old approval for a changed merge target; BOSS adds
new check/review receipts and preserves original review. No source copied.

Contract agreed: current target must descend from original base; merge candidate
has exact parents [target,original approved]; preserve complete full original-base
and target diffs + check output transiently, persist only bounded receipts/hashes.
No retry after second drift, conflict, Stop, invalid evidence or cleanup unknown.

Foundation: migration AddMergeIntegrationEvidence (20261027050000) adds new stage
input/receipt guards and a shared read-only SQL evidence projection for intent,
publication and Done lineage. Context revalidates persisted Verdict reports,
including no outstanding issues for approval. Independent review caught the raw
SQL nonempty-issues bypass; original and merge approvals now reject it. Existing
fast-forward context fixtures now explicitly pin candidate workspace/review ID.

`rtk proxy asdf exec mix test test/boss/deliveries_test.exs
test/boss/delivery_protocol_test.exs`:16 passed,seed509647 before the additional
persisted-review hardening; final combined baseline rerun underway. Root Githelper
f688a41 cherry-picked asf56e043. Existing native target-drift test now requires fresh
merged Done with exact two parents and preserved concurrent file. New failure,
Stop, Repo-loss native cases assigned to UI agent in a separate test file. No paid
providers. Core checkpoint is for combined verification, not completed acceptance.
