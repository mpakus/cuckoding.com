# 2026-10-25 — BOSS-003a manual spec import

## Scope and baseline

- Clean main d180fcb. Reuse root's managed checkout on codex/boss-spec-import.
- Bounded Markdown scan, optional real YAML parsing, atomic full-scan
  reconciliation, retained missing history, manual Sync and a minimal task list.
  No polling, execution, workflow transitions or full Kanban in this increment.
- Parent owns scanner/persistence/migrations/shared docs. Bootstrap agent owns
  document parser + dependency/lockfile/tests in codex/boss-spec-parser; git_spike
  agent owns four UI/router/test files in codex/boss-spec-sync-ui. Each writer
  has its own managed worktree. folder_picker_review is independent read-only review.
- Continue RTK, Ponytail, TDD, reference coding and explicit test scope.

## Research / decisions

- xerj `frontmatter parse` and `scan duplicate identity` returned weak unrelated
  hits. Fall back to concrete symbols/rg and read actual source, not search misses.
- Kander dea0ba6b885c39a56ee769223f7fa5c054e68c70:
  internal/board/scan.go:30–94 and summary_refresh.go:17–80 reject incomplete scans;
  internal/fs/posix.go:222–269 and fifo_unix_test.go demonstrate regular-file,
  no-follow and nonblocking descriptors. Adopt complete-or-no-write reconciliation
  and explicit file-type checks. Portable Elixir checks are not openat/O_NOFOLLOW;
  do not claim protection against all hostile concurrent filesystem replacements.
- Keep scan and commit within one bounded immediate SQLite transaction so slower
  scans cannot publish stale observations after newer ones. This deliberately
  holds the write lock during local reads; failure/timeout rolls back the import.
- Current path uniqueness applies only to present specs. Missing histories retain
  identity/revisions/tasks, enabling path reuse and explicit-ID path swaps without
  merging histories. Only a complete valid manifest can set missing flags.
- Parser and UI agents will supply pinned source/dependency/test evidence before
  integration. Backend contract: SpecImporter.sync(project_id) returns counts or
  path-specific errors; Projects.list_spec_entries(project_id) supplies task list.

## Progress

- Acceptance tests and implementation in progress; no completion claimed yet.

- Integrated parser commit 3b53bec. Added supervised imports (four workers,
  10-second independent deadline, 8-million-word heap ceiling) and pinned Repo
  PID so an old worker cannot resolve a newly restarted Repo by its name. The
  supervisor stops imports before Repo and before application lock release.
- Timeout/worker death has an unknown result if commit already completed; report
  interruption, not a rollback guarantee. UI refreshes persisted entries on errors.
- Backend tests: initial missing-module RED; focused importer/persistence/lifecycle
  20 passed after implementation. Full combined backend/parser suite 86 passed.
  One earlier teardown failed while deleting scratch WAL sidecars; Exqlite's
  close_v2 explicitly defers finalization (deps/exqlite/c_src/sqlite3_nif.c:660).
  Scratch cleanup now narrowly retries eexist/enotempty in its exclusively owned
  directory after supervised processes stop. No existing directory is cleared.
- Mutation: doubled total-byte guard; test spec_importer_test.exs:227 failed with
  nine imported files and one missing record instead of rejection. Restored guard.
- Commands: `rtk proxy asdf exec mix deps.get`, `mix format`, `mix test`, focused
  `mix test test/boss/spec_importer_test.exs test/boss/spec_persistence_test.exs
  test/boss/application_test.exs` (all mix commands through rtk proxy asdf exec).
- Review found explicit YAML binary tags can erase type into invalid UTF-8; parser
  owner is adding regression and boundary checks before final integration.
