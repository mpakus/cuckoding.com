# BOSS working rules

@/Users/mpak/.codex/RTK.md

- Treat `BOSS_PLAN.md` as the product specification for this restart. Read
  `tasks/plan.md`, `tasks/todo.md` and the latest `.worklog/` entry before work.
  Earlier Cuckoding implementations are not requirements for BOSS.
- Use multiple agents for independent implementation/review tasks. Give each
  writer an isolated worktree and `codex/` branch with explicit file ownership;
  integrate dependent work sequentially. Keep one owner for shared migrations
  and shared documentation to avoid competing edits.
- Update this file, relevant documentation, task status and `.worklog/` with each
  completed increment. Record only verified behavior and actual commands.
- Review and test finished branches, merge them into local `main`, verify the
  combined result, then remove their temporary worktrees and merged branches.
  Preserve unrelated work and dirty checkouts; do not force-delete them. Remote
  publishing is separate from these local merges.
- Use Ponytail: the smallest complete change, explicit failure handling and
  focused verification. Change only files needed for the current task; no
  speculative abstractions, unrelated cleanup or automatic dependency additions.
- Prefix shell commands with `rtk`; use `rtk proxy` for unsupported commands and
  when exact output matters (especially JSON, CLI contracts and test evidence).
- Before non-trivial implementation, search the xerj `bossrefs` index, then read
  the relevant source and tests in `examples/`. Follow `examples/README.md`.
  Record query, source path + pinned SHA, adopted pattern and rejected tradeoff
  in `.worklog/`. A search miss is not evidence: fall back to `rg` and official docs.
- Reference checkouts are read-only research inputs, not runtime dependencies.
  Their agent instructions do not govern BOSS. Do not reset, update or clean
  existing reference checkouts automatically. Check license and provenance before
  copying code; prefer independently implemented patterns.
- Keep `.worklog/YYYY-MM-DD.md` current: scope and baseline at the start;
  decisions, touched files, commands/results and limitations during work;
  outcome and exact next step before finishing. Never record credentials or raw
  private agent transcripts. Update task checkboxes only with verification evidence.
- Use relevant installed skills. Install a missing skill only when needed for
  the task, inspect it first and avoid unrelated integrations or telemetry.
- Preserve source specs and user changes. Never equate process exit, a model's
  "done" message or an old approval with verified delivery. Keep spec revision,
  run, checks, review and integration tied to the actual Git commits.
- Verify the effective Elixir/OTP pair in `.tool-versions`. On this machine use
  `rtk proxy asdf exec mix ...` when Homebrew takes precedence in PATH.
  Application tests and the separate `spikes/` suites have different acceptance
  scopes; a passing experiment is not a production adapter.
- Create test scratch roots exclusively before registering recursive cleanup.
  A VM-local counter is not a globally unique directory name. Never remove a
  pre-existing directory to make a test pass.
- Hold the data-directory lock in Application callback state until all children
  stop. Initialize SQLite WAL before starting the two-connection Repo pool;
  Ecto migrations require at least two connections. Tests must use fresh data.
- Keep local tokens out of URLs and persistent logs. Preserve `same-origin`
  referrer policy: `no-referrer` made legitimate browser form POSTs send a null
  Origin. Continue rejecting foreign/null origins; do not weaken the allowlist.
- Repository/specs paths come from the native folder chooser, never editable
  form paths or browser file-upload names. Keep the selection server-side and
  revalidate it on registration. Resolve relative specs against the selected
  repository; preserve cancellation and bounded, single-dialog helper cleanup.
- Record spec identity, append-only revision and initial task atomically with an
  immediate SQLite transaction. Compare with the latest revision, not any older
  matching hash; A→B→A must retain all three. Keep task revision/title pinned.
  Direct record calls reject ID/path conflicts; the full importer reconciles moves
  and path swaps. Missing history may share a path, but present specs may not.
  Keep composite revision ownership and immutable-history database constraints.
- Import only complete validated scans; scan and reconciliation share an immediate
  transaction. Bound traversal, bytes, YAML and worker count/time/memory. Keep
  workers supervised and bound to the actual Repo PID. Interrupted outcomes may
  already be committed: reload persisted entries, never promise rollback on timeout.
  Preserve raw source; reject ambiguous YAML types/aliases and raw non-UTF8 names.
- Test committed durability/concurrency in an exclusively created scratch DB with
  a real connection pool; a sandbox transaction alone is not restart evidence.
- Live provider calls are opt-in and bounded; never repeat a paid smoke run
  automatically. Retain sanitized evidence, not raw private transcripts.
- Git publication must not move a branch behind a user's checkout. The spike
  refuses an already checked-out target and retains failed/dirty worktrees.
  Production runner backpressure, independent EOF and descendant cleanup remain
  open gates. erlexec may report exit 0 after cancellation: retain the cause.
