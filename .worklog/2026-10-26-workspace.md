# First manual run — workspace layer

- Baseline609df38; own branch codex/boss-run-workspace and only Workspace module,
  focused tests and this log. Root owns persistence/shared docs/UI.
- Read current AGENTS, plan/task context, repository validation and Git spike.
- xerj `createWorktree base branch existing dirty` was weak; used rg fallback.
  Read AO Apache-2.0 7193eff4e08f1481944845ee058fe6fd18930b6d
  backend/internal/adapters/workspace/gitworktree/workspace.go:275 and commands.go.
  Adopt full pinned base and ordinary argv worktree creation; reject forced
  reconstruction, auto branch suffixes, force/prune/remove and reference movement.
- Contract: read-only plan, persisted intent at caller, prepare fresh or validate
  existing, inspect read-only. Keep output and propagate cleanup_unknown.
- Bounded production Git transport is Boss.Agents.Process from the sibling writer.
  Focused tests initially inject a local Git runner to verify Git semantics;
  production native transport integration still required before final acceptance.

## Implementation and verification

- Added read-only plan and inspect; prepare creates ordinary fresh branch/worktree
  from the full saved commit or validates an existing matching tree. No cleanup,
  reconstruction, force, reset, branch movement, fetch or automatic repository edits.
- Command arrays disable hooks/fsmonitor/submodules/network protocols, clear GIT_*
  overrides and global/system config, disable lazy fetch/replacement objects.
  Stdout capture is bounded to1MiB; error output is never returned or logged.
- A Git command lacking native group_empty receipt returns cleanup_unknown,
  including successful worktree creation followed by unknown transport outcome.
- Added fixed errors for executable filter drivers and repository conditional
  includes. Independent review reproduced includeIf.onbranch enabling a smudge
  only on the new codex branch; our RED regression accepted it before the fix,
  and now both plan and prepare reject it before checkout.
- Review also found macOS /var aliases in configured test data_dir. Resolve only
  the trusted data root with a40-link bound, then require generated descendants
  to stay symlink-free and physically outside the source checkout. Alias/cycle,
  missing-output, foreign-worktree and immutable base/dirty preservation tests pass.
- RED command against stub:6 failures. Current focused command:
  `rtk proxy asdf exec elixir -r lib/boss/agents/workspace.ex -e 'ExUnit.start(exclude: [:native]); Code.require_file("test/boss/agent_workspace_test.exs")'`
  passed13 tests,1 native integration test excluded (2.5s, seed221288).
- The fixture runner executes real Git to verify repository semantics; it is not
  the production transport and does not prove native cleanup. New macOS native
  integration test runs by default in mix test after Process integration.
  Standalone compilation currently warns that the sibling Process module is
  unavailable; do not count this as a warnings-as-errors application build.
- Direct Elixir formatter applied to both source/test files. Root will run the
  application formatter, compiler and full suite after integrating dependencies.

- Independent review accepted the source fixes, contingent on production native
  integration test after merge. At root's request added :cancelled propagation
  when native group cleanup is proved; cleanup_unknown still takes precedence.
  Final focused run:14 passed,1 native test excluded (seed468842). No extra scope.
- Root handles shared docs/main integration and final native/application evidence.
- Staged diff check caught an extra formatter-added blank line at each EOF;
  removed it and repeated diff check before delivering the commit.
