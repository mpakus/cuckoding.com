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
