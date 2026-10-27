# Delivery Git helper — 2026-10-26

## Scope and baseline

- Isolated branch `codex/boss-delivery-git`, starting at `17c2bc3`.
- Own the integration helper, reusable candidate tree verification and focused
  real-Git tests. The parent owns delivery persistence, workers, shared docs,
  AGENTS.md, task tracking and final integration.
- Runtime verified with `rtk proxy asdf exec elixir --version`: Elixir 1.20.3,
  OTP 28; `.tool-versions` specifies `1.20.3-otp-28`.
- Skills: Ponytail for the smallest complete behavior; Git workflow for the
  isolated branch and review/test handoff. The existing dependency checkout was
  linked temporarily for compilation; no dependency changes.

## Reference coding

- Searched xerj `bossrefs` for `update-ref`, `mergeRunBranch`, `FinalizeReviewRun`,
  `runWithRetry` and `validateDispatchFix`; weak query matches were followed by
  direct `rg` and source/test reads in the pinned `examples/` checkouts.
- `examples/kander/internal/review/disposition.go` (196–240) and
  `internal/board/review_closure.go` (257–269, 431–489), MIT,
  `dea0ba6b885c39a56ee769223f7fa5c054e68c70`: adopt exact candidate/head checking
  across Git work and compare-and-set evidence boundaries; do not copy code.
- `examples/agent-orchestrator/backend/internal/service/pr/action_service.go`
  (132–171), its test (261–277), Apache-2.0,
  `7193eff4e08f1481944845ee058fe6fd18930b6d`: adopt saved SHA before/after readiness;
  reject the unrelated hosted PR machinery.
- `examples/backlog/packages/core/src/run-merge.ts` (189–258), run-service and
  merge tests, Apache-2.0, `3580cfbbb1be4144a5cca5b49190e1f8158e4cf7`: reject
  merging into a user's checkout and treating merge success as completion.
- Existing `spikes/git/safety_test.exs`: retain the ordinary dedicated worktree
  reservation and checked-out-target refusal; add persisted-intent-compatible
  publication of the exact candidate with saved-old-SHA CAS.

## Implementation

- `Candidate.verify_tree(path, sha, opts)` reuses the fresh private-index capture
  so a planner or publication workspace may have attached HEAD while verifying
  the exact top-level path, HEAD before/after, status and reconstructed tree.
  Existing `Candidate.verify` still requires its generated candidate intent,
  linked-worktree identity, retained ref and detached HEAD.
- Integration uses only ordinary worktree
  creation, exact reviewed SHA fast-forward and Git `update-ref --no-deref` with
  the original base SHA. Source branches/index/files are not rewritten.
- `plan/6`, `prepare/2`, `publish/2`, `verify_published/2` use saved string-key
  intent. Paths are regenerated from the physical BOSS data root, project and
  delivery UUID. A candidate must share project/repository/common-dir/base-branch
  identity and descend from the original saved base. A fix can begin from an
  earlier candidate; its nested run base need not equal the original delivery base.
- Publication requires the target's exact original SHA and an exclusively reserved
  ordinary target checkout. An optional `:authorize` callback runs after helper
  prechecks immediately before CAS, letting the worker revalidate persisted task,
  revision, review and publication intent. Callback failure does not publish.
- Unknown CAS outcomes or any failure after a successful CAS report
  `:publication_unknown`; there is no rollback. Failed/dirty workspaces remain.
- After successful post-publication checks, `release/2` verifies the owned checkout,
  switches only that checkout to detached candidate HEAD, then verifies it again.
  It does not reset, clean or delete files. This retains evidence while freeing
  the branch for the next delivery. Dirty release blocks completion.
- `verify_published/2` accepts exact attached target or detached exact candidate.
  A detached verified checkout no longer needs exclusive ownership of the target,
  but the actual target ref must still equal the reviewed candidate. `prepare/2`
  and `publish/2` continue requiring the attached target.

## Verification and limitations

- `rtk proxy asdf exec mix format ...` passed for the four owned source/test files.
- Initial combined candidate/integration run: 19/20 passed in 121.1 seconds;
  repeat-prepare exposed validation order only (existing owned path incorrectly
  reported as checked-out target). Reordered the existence check before branch
  occupancy.
- `rtk proxy asdf exec mix test test/boss/check_candidate_test.exs`: 9 passed in
  31.2 seconds, including attached-HEAD verification and hidden index-flag edits.
- `rtk proxy asdf exec mix test test/boss/delivery_integration_test.exs`: 13 passed
  in 105.7 seconds before adding the explicit successful-release behavior.
- Final `rtk proxy asdf exec mix test test/boss/delivery_integration_test.exs`:
  14 passed in 128.2 seconds. Covers dirty user checkout/index preservation,
  checked-out target anywhere, saved-old-SHA CAS drift, symbolic/symlink target
  refusal, hidden candidate/workspace edits, forged path/common-dir/metadata,
  pre-existing-directory retention, post-publication mutation, unknown CAS,
  post-CAS checkout failure, persisted authorization refusal, Stop, SHA256,
  safe release/re-acquisition and detached-before-publication refusal.
- `rtk proxy asdf exec mix compile --warnings-as-errors` and
  `rtk proxy git diff --check` passed again after the release addition.
- `rtk proxy asdf exec mix format --check-formatted` for the four owned
  source/test files passed after the release addition.
- Git 2.51.1 scratch experiment confirmed `update-ref --no-deref` can replace a
  symbolic ref when its referent has the expected SHA. Existing symbolic refs
  and symlink aliases are refused before publication. This does not protect
  against a deliberately concurrent symbolic-ref rewrite between the precheck
  and CAS; Git's normal worktree/ref locking and expected-SHA CAS are the boundary.
  The parent explicitly accepted documenting that limit rather than introducing
  a custom refs backend or interactive Git transaction transport.
- No provider calls or reference-project test suites were run.

## Outcome and next step

The helper and its focused safety tests are complete. The parent owns review of
the full worker/persistence/UI integration, combined verification, merge to local
main and removal of the merged development worktree/branch. The helper itself
does not create task evidence or claim Done, and never deletes run artifacts.
