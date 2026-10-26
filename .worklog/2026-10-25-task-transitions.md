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

## Outcome and next step

In progress: settle a small command contract, implement policy plus transactional
storage, verify replay/concurrency/rollback/restart, then review and integrate.
