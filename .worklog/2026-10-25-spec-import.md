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
  holds the write lock during local reads; failures before commit roll back the
  import, while interruption after commit has an unknown observed outcome.
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


## Integrated verification

- Parser 3b53bec plus review fix c315f37; scanner 1ef1ac8; UI 96f889b.
  Parser reference: Agent Orchestrator 7193eff4e08f1481944845ee058fe6fd18930b6d,
  frontend/src/renderer/lib/markdown-frontmatter.ts and test; adopted anchored
  delimiter/BOM/CRLF/raw source separation, rejected handwritten YAML subset.
  yaml_elixir 2.12.2 MIT commit 4c5ee0408014a6e999dca4869e39eeca0e58a2c2 and
  yamerl 0.10.0 BSD-2-Clause commit 39981b9cb9d9edc227cf43a3e19dd16869493553.
- Parser rejects binary tags before Mapper strips YAML types and checks UTF-8.
  Aliases are rejected after a reproduced upstream flow-collection alias defect.
  Parser has an independent 500ms timer and 2-million-word heap ceiling.
- UI reference: Backlog 3580cfbbb1be4144a5cca5b49190e1f8158e4cf7,
  packages/server/src/routes/integrations.ts:164, IntegrationsView.svelte:545/1064,
  source-state.test.ts:128. Query importPulledTasks. Adopted busy/counts/refresh;
  rejected cloud integration and raw exception messages. Busy-guard mutation in
  memory was caught by the UI test. Seven new UI tests; no full Kanban claim.
- Review of raw filename behavior led to :file.list_dir_all + explicit UTF-8
  rejection. OTP official docs distinguish list_dir omission from list_dir_all.
  macOS probe returned eilseq before creating the file. Linux-only regression
  remains skipped here; no Linux execution claimed.
- Combined worktree: `rtk proxy asdf exec mix test` — 94 passed, 1 skipped;
  `mix compile --warnings-as-errors`, `mix format --check-formatted`,
  `mix assets.build`, `mix assets.deploy`, `rtk git diff --check` passed
  (mix commands through rtk proxy asdf exec).
- Browser smoke used its own exclusively created repo/data directory and server.
  Project registered through backend setup; this run tests Sync, not native chooser
  acceptance. Browser login, empty list, three-file import, repeat no-op, edit with
  source2/task1, retained missing task, duplicate-ID rejection, retry and reload
  verified through visible UI. Console errors/warnings: none in this IAB run.
  Screenshot: /Users/mpak/.codex/visualizations/2026/10/25/01a173ec-2089-7ff3-88a7-142cfa5d8f78/boss-spec-sync.png.
- Closed smoke tab, stopped only owned process group 37202, removed owned temporary
  data/repository and the earlier test scratch remainder. One-use test token was
  consumed and its mode0600 temporary transfer file removed; no token logged.
- Updated AGENTS, README, plan/todo and reference research to shipped behavior.
  BOSS_PLAN unchanged. Source files are never rewritten. No provider calls/push.

## Limitations and next step

- Manual Sync only; priority/depends_on remain source metadata. Task revision/title
  remain pinned. Next is BOSS-003b bounded polling/debounce + startup rescan, then
  BOSS-004 transitions. Runner reliability gates remain open.
- Portable file checks cannot prevent every hostile concurrent filesystem swap or
  provide an atomic filesystem snapshot. Scan holds the SQLite write lock while
  reading bounded local files. Retained history list has no pagination yet.
- Migration down refuses reused paths rather than deleting history. Interruption
  can occur after commit; UI reloads rather than claiming nothing changed.
- Final local main verification and managed worktree cleanup recorded below after
  integration; completion is not inferred from agent reports alone.

- Final independent read-only review: no blocking findings in integrated code.
  Combined tests and browser evidence above were run by root, not inferred from review.
