# 2026-10-25 — BOSS-002b spec identity, revisions and tasks

## Scope and baseline

- Continue from clean main 2a1d50a and its clean detached managed worktree.
  Reuse that worktree on codex/boss-spec-revisions; no additional checkout needed.
- Finish BOSS-002b persistence only: stable project-scoped identity, immutable
  original-text revisions and a task pinned to a concrete revision, atomically.
  Markdown/YAML import, filesystem reconciliation, UI and execution stay in their
  following tasks. No runtime dependency addition.
- Parent owns schema, migration, context, tests and shared documentation. Separate
  folder_picker_review agent researches the contract and independently reviews.
- Read BOSS_PLAN.md, plan/todo, prior worklog, RTK and Ponytail/TDD/review skills.
  Effective runtime: Elixir 1.20.3 compiled for/running OTP 28 via asdf exec.

## Reference decisions

- xerj `content_hash revision` -> Kander internal/board/transaction_log.go:31 and
  snapshot_context.go:98. Read transaction_log.go and transaction_test.go:150–210,
  at dea0ba6b885c39a56ee769223f7fa5c054e68c70. Adopt monotonic per-identity
  revisions, pinned snapshots and concurrency assertions; reject filesystem
  journals/locks because this increment has only transactional SQLite effects.
- Installed ecto_sqlite3 adapter documents per-call mode: :immediate; use it for
  read-latest + append + task creation without changing global transaction mode.
  Official docs: https://hexdocs.pm/ecto_sqlite3/Ecto.Adapters.SQLite3.html and
  https://hexdocs.pm/ecto_sql/Ecto.Migration.html#references/2. Composite FK keeps
  a task's revision within its own spec. No competitor code is copied.
- Identity is explicit ID or relative path, namespaced to avoid collisions.
  Conflicting explicit ID/path is rejected; rename reconciliation belongs to
  the importer. Latest revision is ordered by number, never unique by hash.
  Tasks stay pinned until an explicit future workflow adopts another revision.

## Implementation and verification

- Added three schemas and one additive migration. Specs have unique project/key
  and project/path; revisions have unique spec/sequence and exact text/hash/path.
  SQLite triggers reject history UPDATE/DELETE, including unpinned revisions.
  Composite task/spec revision FK prevents cross-spec binding; one task per spec.
- Projects.record_spec/2 validates inputs, then reads/writes in one immediate
  transaction. It returns created/unchanged/revised without advancing task pin or
  title. No plan/refined-text columns, parser, watchers or state transitions added.
- SQLite FK errors do not supply a usable constraint name in this adapter. Project
  existence is checked inside the same write transaction for a proper changeset
  error. Database FK remains the final integrity constraint.
- Initial 7 domain tests failed against missing API (RED); all passed after the
  implementation and missing-project error handling. Added 3 adversarial cases
  for forged attributes, exact empty/whitespace source and invalid explicit IDs.
- Separate scratch DB uses a normal two-connection pool, not SQL Sandbox.
  Upgrade preserves pre-existing project; committed revisions/pin survive Repo
  stop/start; eight concurrent equal observations create one revision/task;
  migration down/up succeeds and retains the old project. Tests remove only
  exclusively created scratch roots after supervised Repo shutdown.
- `rtk proxy asdf exec mix test test/boss/spec_revisions_test.exs test/boss/spec_persistence_test.exs`:
  13 passed. `rtk proxy asdf exec mix test`: 52 passed. `mix compile
  --warnings-as-errors` and `mix format --check-formatted` via RTK/asdf passed.
- Mutation checks separately removed UPDATE then DELETE history triggers.
  Each failed exactly the guarded SQL assertion (9/10 domain tests passed);
  original migration restored in finally, then full suite passed.
- Read-only agent review: no blocking findings; latest tests cover frozen title,
  forged fields and deletion of unpinned history. No other writer touched files.
- Scope expands the earlier five-file estimate to seven implementation/test files
  because the public recording API and real-pool durability tests are necessary
  acceptance evidence. Shared docs/worklogs updated by parent only.

## Outcome / next step

- BOSS-002b verified on the branch; local main integration and cleanup follow.
  No user database migrated and no remote publication performed.
- Next: BOSS-003a bounded Markdown scan, optional YAML parsing, complete-scan
  identity/rename/delete reconciliation, idempotent Sync and error preservation.
  Browser UI, polling, runner gates and workflow transitions remain open.
