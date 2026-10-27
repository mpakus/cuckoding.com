# Managed delivery pipeline

- Scope: typed plan, bounded implementation/check/review/fix worker, shared private
  report-file lifecycle; root owns persistence/Manager/task transitions and docs.
  Baseline17c2bc3 on isolated codex/boss-delivery-pipeline. No provider calls.
- Applied RTK/Ponytail. Query `xerj search --prefix bossrefs runWithRetry -k 2
  --full 1600` found Backlog retry.ts40. Read retry.ts40–61 and
  retry.test.ts20–51/73–90, pinned3580cfbbb1be4144a5cca5b49190e1f8158e4cf7,
  Apache2. Adopt bounded attempts and prior feedback; reject generic retry for
  every failure because Stop/protocol/storage/cleanup errors must halt.
- Reuse existing Codex parser, native runner, Workspace/Candidate and strict
  Verdict decoder. Source specs/check output/feedback are untrusted prompt data.
  Raw check output remains transient and bounded; stored receipts contain hashes
  and counts only.

- Typed plan parser rejects duplicate/unknown keys, invalid UTF-8, wrong shape,
  oversized fields and repeated criteria. Managed reviewer must cover exactly
  the saved plan criterion strings. All prompts refuse inputs over1MiB.
- Extracted unchanged report-file ownership/read validation from manual review
  into Agents.ReportFile for shared planner/reviewer use. Focused protocol +
  prior verdict/Codex tests:16 passed seed987743. Existing real Repo-loss/late
  artifact cleanup regression:1 passed5.2s seed388813 after extraction.

- Implemented owned delivery worker: plan read-only against exact saved base;
  fresh implementation worktree per cycle; separate persisted snapshot intent and
  candidate SHA; explicit saved argv checks; fresh read-only strict review over
  full original-base diff, complete bounded check output and prior feedback.
  Fixes start at the exact rejected candidate and never mutate prior worktrees.
- Output capture is transient, combined <=1 MiB and UTF-8 complete, with actual
  exit/EOF/group cleanup plus exact before/after tree verification. DB receipts
  retain only hashes/counts and typed reports. Exported run_check/3 supports the
  parent's integration worker using the same proof contract.
- Retry only complete nonzero check exits or changes_requested. Normalize feedback
  and bind repeated-failure detection to tree/config; at most three total cycles.
  Stop/protocol/input/cleanup/storage failure halts; needs_spec_revision requests
  input; approval yields ready_to_merge, never Done.
- Merged context checkpoint 0f724aa and Candidate.verify_tree checkpoint10a767d
  sequentially. Production transport suite:12 passed103.8s seed181815. Covers
  approved/restart/replay, reject→fix→approve, check→fix, prior feedback and full
  original-base diff, untouched prior worktrees, repeated failure and max3,
  invalid/mutating plan/check/report, needs_input and suspended-Manager Stop.
- Tightened Stop immediately before Codex spawn and normalized whitespace/order
  in repeated feedback. Added lost-intent/Repo-loss quarantine tests. Targeted
  command: mix test delivery_worker_test.exs locations167/213/233/248 plus
  delivery_check_test.exs and delivery_protocol_test.exs:11 passed10 excluded,
  23.3s seed197719. All commands used rtk proxy asdf exec and full test/boss paths.
- No runtime dependency added. No paid/provider invocation. Parent owns combined
  context/integration/UI validation and main merge; integration code not yet in
  this branch emits the expected missing IntegrationWorker compile warning.
