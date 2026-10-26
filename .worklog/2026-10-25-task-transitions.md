# BOSS-004 — persisted task transitions

## Scope and baseline

- Continue from clean local main `ccc4999`; primary task checkout reused on
  `codex/boss-task-transitions`. Previous application evidence: 113 passed,
  1 Linux-only skipped. No baseline suite rerun yet.
- Persist allowed commands and immutable task events atomically; fence stale
  commands and replay conflicts. Keep recovery reasons and snapshot pins.
- Run/check/review/integration producers are absent. Their transitions must
  fail closed, without accepting caller-supplied evidence as verification.
  No agent execution or board UI in this increment.
- Root owns context/schema/migration, persistence verification and shared docs;
  isolated writer owns pure policy/tests; independent reviewer owns no files.

## Reference coding

- `rtk proxy xerj search --prefix bossrefs 'transition expected state completion evidence' -k 3 --full 1600`
  returned unrelated updater/UI hits. Narrowed to `verifyClosureHead` and read
  pinned Kander source/tests after reviewer identified transaction/dispatch code.
- Kander MIT snapshot `dea0ba6b885c39a56ee769223f7fa5c054e68c70`:
  `internal/board/transaction.go:214`, `internal/board/dispatch_test.go:54`,
  `internal/review/disposition.go:196`, `internal/board/review_closure.go:431`.
  Adopt monotonic version checks, command receipts and immutable events;
  validate actual persisted evidence before success. Reject its dispatcher and
  file-journal scaffolding; independently implement the smaller SQLite contract.

## Progress

- Read product state graph and exact quality gates, task plan/status, existing
  task schema and revision migration. Existing tasks have state `new`, no
  version or events; revisions are already append-only and tasks stay pinned.
- Read-only agent reviewed policy, idempotency and missing-producer boundaries.
- Confirmed effective Elixir 1.20.3/OTP 28 with
  `rtk proxy asdf exec elixir --version`. Read installed adapter 0.26.0's
  `deps/ecto_sqlite3/lib/ecto/adapters/sqlite3.ex:203` transaction-mode contract.
- Context/schema/migration committed as `c2f5e0c`. The initial focused test
  command failed to compile because the new Event/context did not exist yet;
  policy integration and GREEN run are pending. No passing test claim yet.
- Writers use separate managed `boss-transition-policy` and
  `boss-transition-persistence` worktrees; ownership is respectively pure
  policy/tests and the existing real-pool persistence test file. Reviewer is
  read-only. Root owns shared docs and migration.
- Policy commit `4257661` integrated after reading both module and tests.
  `rtk proxy asdf exec mix test test/boss/tasks_test.exs test/boss/tasks/transition_test.exs`
  passes 20 tests on root. Policy writer's earlier full run found 7 failures in
  the old real-pool fixture migration list; its owner is updating that list and
  migration rollback expectations (not a product database failure).
- Independent review found that resolving a registered Repo name again inside
  the command could reach a replacement pool after restart. `f898f1c` pins the
  actual Repo PID and restores the caller's selector; missing/dead Repo returns
  `:storage_error`. Writer is reproducing the defect and checking the fix against
  a real named scratch Repo. Never claim rollback for unknown connection outcomes.
- Source review of nested DBConnection transactions confirms exceptions/rollback
  abort the outer transaction; documented that success is provisional until outer
  commit and outer transaction mode is inherited.

## Verification and review

- Persistence writer commit `8e87e7e` integrated after source review. Its focused
  `rtk proxy asdf exec mix test test/boss/spec_persistence_test.exs` passed 14/14.
  Seven new cases cover concurrent exact receipts, distinct-command CAS, committed
  same-file restart/replay, named Repo replacement, unavailable selectors,
  pre-existing task upgrade/down/up and retained-history downgrade refusal.
- Meaningful regression RED on `4257661`: after a named Repo was replaced,
  transition returned `:storage_error` and zero events, but the replacement task
  had become blocked/version 1. GREEN on `aeb5307`: task/event unchanged, caller
  selector restored, identical command retry succeeds after removing the injected
  event failure. The fixture uses a `VACUUM INTO` copy and keeps the old query-cache
  ETS alive for the paused SELECT's bookkeeping; it isolates name rebinding from
  SQLite's still-held old-file lock. Same-file restart is a separate passing test.
- The initial snapshot fixture produced a lock warning before WAL initialization;
  the final fixture initializes WAL before the two-connection replacement pool.
  Final focused/root runs have no such warning.
- `aeb5307` also refuses migration rollback when any task event exists. The
  regression verifies unchanged task/recovery/version, event, migration version
  and immutable-history triggers after refusal. Empty-history down/up works.
- Root `rtk proxy asdf exec mix test`: **140 passed, 1 skipped**, seed 755117.
  `rtk proxy asdf exec mix compile --warnings-as-errors`,
  `rtk proxy asdf exec mix format --check-formatted` and
  `rtk proxy git diff --check` passed. The skip is the existing Linux-only test.
- Independent reviewer checked context/policy/migration plus regression evidence;
  final verdict has no remaining blockers. Reviewer did not run additional tests.
- Updated AGENTS, README, research, task plan/status and TASK_WORKFLOW contract.
  BOSS_PLAN remains unchanged. No new dependency, UI/browser/asset run, paid
  provider call, remote publication or spike retest in this backend increment.

## Outcome and next step

Backend foundation is verified: commands and immutable receipts, saved recovery,
stale/replay protection and Repo lifetime fencing. All producer-dependent forward
and recovery transitions remain closed. Positive commit-bound evidence validation
is still open and is not marked complete in tasks/todo.md.

Merged into local main as `daa1c0f` (documentation/implementation tip `0ae1ade`).
On main, `rtk proxy asdf exec mix test` again passed **140 tests, 1 skipped**,
seed 252557; compile with warnings-as-errors and formatter check also passed.

Both writer worktrees were clean, then archived through Codex and confirmed absent
from `git worktree list`; all three merged `codex/boss-transition-*` /
`codex/boss-task-transitions` branches were deleted. The first branch-deletion
attempt ran while archival was queued and correctly refused active checkouts;
it succeeded after archival completed. The primary managed worktree remains
clean/detached because Codex identifies it as the task's non-removable primary
checkout (established in prior increments). No forced cleanup or remote push.

Next product increment: BOSS-005 board and task drawer. Runner reliability and
positive quality gates remain open until their later evidence producers exist.
