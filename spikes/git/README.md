# Git safety spike — BOSS-000b

Run from the project root:

```sh
rtk proxy elixir spikes/git/safety_test.exs
rtk proxy mix format --check-formatted spikes/git/safety_test.exs
```

This standalone ExUnit experiment needs only Git and Elixir. It creates fresh
temporary repositories, runs Git through `System.cmd/3` argument arrays, and
removes its test-owned roots afterward. It accepts no repository/path arguments.
Each root uses a cryptographically random name and exclusive directory creation;
cleanup is registered only after creation succeeds, never for a pre-existing path.
Inherited `GIT_*` variables and global Git configuration cannot redirect these
scratch operations. The helper module is deliberately **not application code**.

## Verified policy

1. Record full base SHAs before creating task branches. Two linked worktrees
   start from that commit even when the target has advanced. Source checkout
   HEAD, index, tracked edits and untracked files stay unchanged during work.
   Linked worktrees share Git objects/refs; this is isolation, not a sandbox.
2. Reopen only when repository identity, branch and base ancestry agree. Keep
   current commits and edits; mismatches fail without repair/reset. A missing
   directory with an existing task branch currently fails safely rather than
   automatically reconstructing it.
3. Prepare a detached integration worktree at the expected target SHA, merge
   the exact task commit there, then run checks against that candidate SHA.
   Conflicts retain the integration worktree and unresolved index. Target drift
   before preparation prevents the attempt.
4. Publication requires the same clean candidate HEAD and expected target SHA.
   Acquire the target with ordinary `git worktree add <owned-path> <target>`.
   **If the target is checked out anywhere, publication refuses.** That includes
   a clean user source checkout and any linked checkout. Never override this
   guard with `--force`, `update-ref`, stash, reset or automatic detach.
5. When the target is available, recheck its HEAD after acquiring the owned
   checkout, then `git merge --ff-only <checked-candidate-SHA>` there. The source
   checkout remains untouched. This spike does not automatically free a user's
   target branch; manual integration or an explicit user checkout change is
   required. A refusal is actionable `ready_to_merge`/attention, never Done.
6. Cleanup requires no tracked, untracked **or ignored** files and proof that
   the worktree HEAD is an ancestor of the recorded integrated commit. Remove
   with ordinary `git worktree remove`; preserve branches in this experiment.
   Failure keeps evidence. Never use forced removal, reset, clean or global prune.

The script's `checked` argument represents the SHA returned by future checks;
passing a SHA here does not establish real check/review success. Twelve tests
exercise successful publication as well as refusals and preserved on-disk state.

## Evidence and limits

On 2026-10-25, macOS, Git 2.51.1, Elixir 1.19.5 / OTP 28:

- 12 tests passed; the initial unimplemented version failed all 12.
- 12 tests also passed with bogus inherited `GIT_DIR` and `GIT_WORK_TREE`.
- Temporary mutation copies caught removal of the target guard (1 failure),
  removal of candidate SHA validation (1), forced target checkout (2), and
  dropping ignored-file preservation (1). The source was not mutated.

Before production use, add persistent ownership/intent records, canonical path
authorization, one integration queue per Git common directory, check/review
evidence tied to spec revision and commits, and recovery at each effect boundary.
Normal Git checkout guards are not a lock against an external process using
forced checkout or direct ref mutation. Concurrent external Git writes, crashes
mid-publication, submodules, hooks/filters and Linux remain untested. A failure
after publication must preserve the resulting commit and require attention;
automatic rollback of user history is outside this policy.

## Reference coding

Queries and exact commands are recorded in
[the worklog](../../.worklog/2026-10-25-git.md). No source was copied.

- [Kander closure guard](https://github.com/dualface/kander/blob/dea0ba6b885c39a56ee769223f7fa5c054e68c70/internal/review/disposition.go#L196)
  and [its real Git test](https://github.com/dualface/kander/blob/dea0ba6b885c39a56ee769223f7fa5c054e68c70/internal/review/disposition_test.go#L29):
  use exact HEAD and clean status; omit the review DSL.
- [Orchestrator removal arguments](https://github.com/OrchestratorInc/agent-orchestrator/blob/7193eff4e08f1481944845ee058fe6fd18930b6d/backend/internal/adapters/workspace/gitworktree/commands.go#L49)
  and [dirty-tree test](https://github.com/OrchestratorInc/agent-orchestrator/blob/7193eff4e08f1481944845ee058fe6fd18930b6d/backend/internal/adapters/workspace/gitworktree/workspace_integration_test.go#L493):
  use non-forced removal; additionally preserve ignored files instead of treating
  every ignored file as disposable generated data. Omit force/prune recovery.
- Official contracts: [worktree](https://git-scm.com/docs/git-worktree),
  [merge](https://git-scm.com/docs/git-merge),
  [update-ref](https://git-scm.com/docs/git-update-ref),
  [System.cmd/3](https://hexdocs.pm/elixir/1.19.5/System.html#cmd/3).
