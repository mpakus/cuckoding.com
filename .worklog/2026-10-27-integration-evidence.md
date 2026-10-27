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

Core baseline command (Deliveries context + Protocol + existing integration worker)
completed23 passed,seed633133,110.4s, including fresh divergent Done with exact two
parents and a retained parallel target file. Fixture target_diff now compares to
actual read-only Git diff, permitting a legitimate empty delta when parallel
candidates make identical changes.

Additional context/SQL regressions bind original review/check/plan, fresh candidate
identity, target/candidate SHA, complete output hash, and publish review ID. SQL
cannot finalize approved merge reports with nonempty, absent, null or object
issues. Context revalidates legacy reports through Verdict.decode; new SQL Ready
report guard also rejects inconsistent persisted approval. Tests also prove no
original-approval fallback after merge begins and preserve original review rows.
A virtual project_id difference was corrected in a history assertion; a negative
admission expectation now follows the existing busy-before-not_ready order.

Focused context/protocol/real-pool upgrade/reviewer/queue suites:29 passed,
seed630807. New pooled upgrade test preserves legacy Ready/history across reversible
migration and valid fast-forward Done, restarts with durable running merge intent,
quarantines it without reexecution, and refuses downgrade with merge history.
New protocol case verifies both complete diffs round-trip and refuses oversized
combined evidence without truncation. Its rerun is pending below.

Final backend verification: context/protocol/merge-persistence/reviewer-persistence/
queue-persistence command passed31 tests,seed50302,1.6s. This includes a dedicated
fresh two-connection pool (not Sandbox) that refuses SQL finalization for approved
merge reports with nonempty/absent/null/object issues, refuses both context and SQL
publication intent, restarts the Repo, verifies no false receipt/intent persisted,
and quarantines the unfinished review. Both new persistence tests use exclusively
created scratch databases. Global mix format --check-formatted and git diff --check
passed; the earlier checkpoint long fixture line is now formatted.

Native extra cases are owned by UI writer: reported10 new native +20 web passed,
including conflict, rewritten history, checks, both review providers, second drift,
Stop and Repo restart. Parent owns verification of that branch and combined full
suite/browser/main. No real-provider or remote publication claims are made here.
Backend implementation and its focused proof are complete; next step is parent
integration of the final backend tests/guards followed by combined acceptance.

Final compile --warnings-as-errors passed. Owned deps symlink removed after all
commands completed; writer checkout clean for parent integration/cleanup.
