# Dependency gate foundation — 2026-10-27

## Scope and baseline

- Isolated writer branch `codex/boss-dependency-gate`, starting at `40c6f1b`.
- Own only `SpecDocument`, new `Tasks.Dependencies`, their focused tests and this
  log. Root owns run/delivery admission, details, UI integration and shared docs.
- Read `BOSS_PLAN.md` dependency requirements, `tasks/plan.md`, `tasks/todo.md`,
  latest main worklog, RTK and Ponytail. No migrations or new dependencies.
- Dependency declarations remain in each task's immutable pinned source revision.
  IDs resolve within its project; source filenames are not aliases.

## Reference research

- Query: `rtk proxy xerj search --prefix bossrefs dependencyReasons -k 3 --full 1800`.
- Read `examples/backlog/packages/core/src/scheduler.ts:108` and
  `examples/backlog/packages/core/src/scheduler.test.ts:48` in the primary checkout.
- Verified Backlog HEAD `3580cfbbb1be4144a5cca5b49190e1f8158e4cf7`; root LICENSE
  Apache-2.0. Adopt independently implemented separation of unknown dependencies
  and waiting dependencies. Only BOSS `done` satisfies an edge. No source copied.
- Reject scheduler weights, leases, concurrent claims and whole-project preload;
  this increment only reads the bounded reachable graph.

## Work in progress

- Added strict `depends_on` metadata validation and shared bounded-parser helper.
- Temporary `deps` symlink points at the existing primary writer dependencies;
  it will be removed before handoff. Local `_build` is isolated.
- Planned bounds: 32 direct IDs, 64 reachable tasks, 8 MiB source, 33 reported
  issues; 1-second traversal budget checked around bounded parser calls. This is
  a soft budget: the existing parser can occupy up to another 500 ms.
- `depends_on: {}` is rejected independently from `[]`: keyword mapping mode
  erases that distinction, so only an empty declared list gets a second decode
  inside the same bounded worker after duplicate-key validation.
- Added read-only `snapshot/2` and `check/2`. The latter returns `:ok`,
  `{:error, {:dependencies_blocked, snapshot}}`, or `{:error, :not_found}`.
  Caller owns the existing Repo-pinned transaction. No nested transaction.
- Reached tasks are memoized; missing references are cached. DFS traverses Done
  nodes for structural failures. Only direct unfinished dependencies get waiting
  reasons. A resource-limit result is blocked and omits the partial direct list.
- Initial baseline test command ran before the expected parser assertion update
  and failed that one old attrs assertion (18/19). Updated the asserted metadata.
- `rtk proxy asdf exec mix test test/boss/spec_document_test.exs
  test/boss/task_dependencies_test.exs`: 30 passed, 0.9s, seed 441200. Includes
  strict YAML types/IDs, preserved order, pinned revisions, project scope,
  filename rejection, diamonds, cycles, missing and malformed source.
- Formatter passed for the four owned source/test files. Resource-limit boundary
  and cache-query evidence are the next focused test increment; not claimed yet.

## Review and resource-bound verification

- Root review found the first implementation fetched source before testing the
  accumulated byte/node budget. Changed the query to return source only when its
  SQLite byte length fits the remaining budget; uncached-node limit now runs
  before another query. Added query telemetry assertions for actual row payload
  bytes and query counts. No raw source is placed in the graph result.
- Preserve retained-source execution: the selected root being marked missing is
  not itself a dependency blocker. Referenced unfinished missing tasks still block.
- `rtk proxy asdf exec mix test test/boss/spec_document_test.exs
  test/boss/task_dependencies_test.exs`: 35 passed, 2.1s, seed 434291.
  Added exact 64/65-task boundary, exact 8-MiB/9-MiB boundary (only 8 MiB returned
  from SQLite), spent time budget, <=33 issues, one lookup per unknown ID and
  diamond node, and missing-root retained-source regression.
- `rtk proxy git diff --check` passed. The time budget is cooperative between
  bounded calls, not a hard wall-clock interrupt for database scheduling.
