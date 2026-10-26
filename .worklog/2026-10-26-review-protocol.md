# Review protocol increment

- Scope: pure bounded verdict validation, bundled output schema and an optional
  Codex review mode. Root owns lifecycle, migrations, UI and shared documentation.
- Baseline: isolated `codex/boss-review-protocol` from local main `6eadd14`.
  Existing implementor parser/summary must keep discarding model and tool text.
- Reference queries: xerj bossrefs `DecodeReviewJSON`, `FinalizeReviewRun`,
  `reviewValidationError`, `verifyClosureHead`. Read pinned Kander
  `dea0ba6b885c39a56ee769223f7fa5c054e68c70` (MIT),
  `internal/board/review_findings.go:43–78,157+` and
  `internal/board/review_gate_test.go:396–413`; Agetor
  `fbd68603afef778a618a94ca88e0c00997956afd` (MIT),
  `src/bun/github.ts:627–637` and matching tests.
- Adopt exact keys, duplicate-key rejection before maps, explicit verdict enums,
  actionable rejection and execution/verdict separation. Reject prose/fence
  extraction, legacy interpretation and raw transcript archives. Implement patterns
  independently in Elixir; no source copied or dependency added.
- Verification commands and results follow after implementation. No provider call.

## Implementation and verification

- `Boss.Reviews.Verdict.decode/1` validates one UTF-8 JSON object up to32KiB,
  required exact keys, nested duplicate keys, field byte/array bounds and verdict
  consistency. JSON pairs remain ordered until exact-key checks; arbitrary prose,
  Markdown fences and trailing JSON cannot supply a verdict.
- After independent design review, final output uses the CLI-designated
  `--output-last-message` file, not a guessed final JSONL agent message. New
  `Codex.args(:review, output_path)` selects read-only, ephemeral execution and the
  bundled schema. Existing parser/summary and implementation argv remain unchanged.
  Root owns the fresh output directory, bounded file read after cleanup, deletion
  and lifecycle verification. This layer alone does not certify model finality.
- Effective runtime: Elixir1.20.3 compiled OTP28, OTP28/ERTS16.4.
- Initial test-first run failed for missing Verdict/protocol APIs (seed331926).
  The final output-file contract replaced the unimplemented stream-capture tests.
- `rtk proxy asdf exec mix test test/boss/review_verdict_test.exs test/boss/codex_test.exs`:
  9 passed, seed435180. Limits include exact32768 bytes, Unicode byte overflows,
  20/21 items, escaped duplicate keys and nested duplicates.
- Mutation converting ordered pairs to a map before validation falsely accepted
  a duplicate verdict; the regression failed (seed740873). Restored immediately,
  then the9 focused tests passed. No mutation remains.
- `rtk proxy asdf exec mix compile --warnings-as-errors`,
  `rtk proxy asdf exec mix format --check-formatted`, `rtk git diff --check`: passed.
- No provider call or live reviewer test. Root integration must verify missing/
  malformed output, real exit/EOF/cleanup, candidate drift, Stop and restart.
