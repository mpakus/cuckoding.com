# Manual check candidate snapshots —2026-10-26

## Scope and baseline

- Baseline main0d4c587; isolated codex/boss-check-snapshot writer.
- Own Candidate helper, minimal Workspace native Git reuse, focused Git tests.
  Root owns persistence/UI/shared documentation. RTK + Ponytail; no newdeps.
- Read BOSS_PLAN exact gates, current plan/todo and last root worklog. Elixir pin
  1.20.3/OTP28; use asdf exec.

## Reference coding

- xerj bossrefs query `verifyClosureHead` found Kander
  `internal/review/disposition.go:196-205` and its callers220/237 at pinned
  dea0ba6b885c39a56ee769223f7fa5c054e68c70 (MIT). Read source and
  `disposition_test.go:53-69` dirty-head regression. Independently adopt exact
  clean HEAD before/after checks; reject importing the competitor review system.
- Candidate captures tracked edits/deletions plus nonignored untracked files with
  two private indexes; matching trees and unchanged source HEAD are observed
  stability, not an atomic filesystem snapshot. Source index/branch/files untouched.
- Retain immutable private ref and separate detached check worktree. Reject sparse
  checkouts/submodules, filters and conditional includes. No reset/merge/remove.

## Implementation and verification

- `Candidate.plan/3` returns JSON-keyed saved intent (original run workspace,
  check UUID/path/ref); root persists before `prepare/2`. Preparation creates a
  parented commit with fixed BOSS identity and CAS-created private ref, then a
  detached check worktree. Exact clean verification runs before returning.
- `Candidate.verify/3` requires linked-worktree gitdir/backlink identity, detached
  exact HEAD/ref, clean staged/untracked status and a newly reconstructed tree.
  Private indexes defeat assume-unchanged/skip-worktree stat flags; forced filemode
  detects executable-bit changes. Source/run branch, HEAD, index bytes and files
  stay unchanged. Ignored files are excluded; ignored check outputs are allowed.
- Reused Workspace native command capture; exposed only safe_config/git helpers
  and private-index env override. Per-Git deadline15s/output1MiB. Unknown cleanup
  remains distinct and preserves private-index scratch; no reconstruction/retry
  of an existing private ref/worktree. Snapshot/index scratch is exclusively
  created; confirmed cleanup removes only its known files and empty directory.
- Initial6 Candidate native/Git tests passed. Added observed-source-drift and
  SHA256 cases. First combined failure was test wrapper `not nil`; fixed to
  `is_nil`, focused drift test passed. No production failure was hidden.
- Final `rtk proxy asdf exec mix test test/boss/check_candidate_test.exs
  test/boss/agent_workspace_test.exs`: **23 passed**,33.3s,seed310077 (8 Candidate,
  15 existing Workspace). `mix compile --warnings-as-errors`, scoped format check
  and `git diff --check` passed.
- Mutation removed only reconstructed-tree equality: hidden index edit regression
  failed expected candidate_changed vs actual :ok,seed863678,exit2. Source restored
  before final suite. Reviewer read source and tests; no source blocker reported.

## Handoff

- Root owns backend/DB/UI integration, final shared docs and local main checks.
- No provider call, merge, source checkout edit or runtime dependency added.
- This is observed Git snapshot/clean-tree evidence, not an atomic filesystem
  snapshot or hostile concurrent filesystem sandbox. Submodule/sparse content
  unsupported; raw output is not persisted. Retained candidates are not approval.
