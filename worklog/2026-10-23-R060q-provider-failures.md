# R060q — Structured Codex failures

Implemented, verified and merged locally. Branch `feature/R060q-provider-failures`, base `dbdf4ad`.
Ponytail full 5.3.2 MIT; adapter, OTP, security, local-runner and quality guidance.
No inference, provider credentials or user workspace access.

Official [app-server errors](https://learn.chatgpt.com/docs/app-server#errors)
describe typed turn failures and upstream status. Official [error guidance](https://developers.openai.com/api/docs/guides/error-codes)
separates usage exhaustion from temporary rate limits, and recommends bounded
backoff/jitter without a server delay. The 0.146.0 offline generated schema
confirms camel-case `usageLimitExceeded`, `serverOverloaded`, `unauthorized`,
HTTP variants and exact error threadId/turnId/willRetry. No Retry-After field is
available there: ambiguous HTTP 429 remains manual, never guessed from messages.

The signed installed desktop binary reports 0.163.0-alpha.11.2, outside admitted
baselines. Only an empty-profile --version was run; no app-server launch or
compatibility expansion. Standalone 0.146.0 generated its schema offline in
private `.ccoding/r060q-schema-bvd_wgkk`, using fresh empty HOME/CODEX_HOME/TMPDIR.
Older historical temporary schema caches were absent. No account/provider read.

Unrelated `Untitled.md.age` remains unread and unstaged.

## Implementation and review

The native task turn parses only typed error discriminants, requiring exact
thread/turn for notifications. A valid internal willRetry stays inside the same
bounded turn; final completion/error still binds that turn. Unknown/malformed
variants stay generic, raw text never controls classification. Usage/session
budgets are nonretryable, HTTP 429 stays manual and explicit overload gains v2
backoff. Cancellation/timeout during internal retry still stop the owned child
and retain the original host edit evidence.

TaskTurn accepts only the new normalized codes and strips error text/reports.
Battles retains existing retry authority; Backoff v2 adds stable 0–2-second
per-attempt jitter to 5/20-second overload waits. Both retries consume the same
task/shared-final counters, exact bindings and deadlines, with all existing drain,
cleanup and fresh-writer-worktree rules. v1 known reasons/delays remain unchanged
and never acquire automatic overload authority. UI distinguishes overload,
ambiguous limit response and usage exhaustion without another setup/action flow.

Applied Ponytail and code-review guidance to connected native parsing, host
normalization, retry eligibility, persistence/admission and public UI paths.
No dependency, migration, runtime baseline, broader grant or account/model
fallback was added. No raw error/provider profile content enters public records.

## Verification

- Focused host tests: **86 passed** (Backoff/TaskTurn/Battles); LiveView **33
  passed**. Final full quality includes the added writer/executor test too.
- `rtk mix quality`: **572 passed**, strict Credo (153 files, no issues),
  Sobelow and dependency audits passed; terminal exit zero. An initial alias
  style finding was corrected before the final run. Existing migration-fixture,
  intentional fault-fixture connection-exit and audit quoted-keyword warnings
  remain; no application compile warning is suppressed.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`:
  **100 passed, 5 ignored**, 224.09 seconds. The unchanged ignored set has two
  consented provider tests plus three selected-runtime/profile environment tests.
  Fixture coverage includes scoped terminal errors, malformed/foreign/canary
  cases, retained edits/cleanup, and internal-retry completion/cancel/timeout.
- Rust format check and locked all-target Clippy with warnings denied passed.
- Mutation disabled overload eligibility: the regression failed as expected;
  exact source restored in finally before the passing final full quality run.
- New receipt/action tests verify jitter/window/v1 compatibility, quota refusal,
  manual 429, fresh claims, unchanged deadline and exhaustion at exactly two
  retries. The real executor retains writer changes and immutable failed receipts.
  LiveView verifies action availability and reconnect for all three new codes.
- Local Markdown targets: **292** verified;
  whitespace checks passed. No visual browser pass was claimed for these copy/
  state changes.
- `rtk proxy bin/dev.build`: passed, strict/deep sealed receipt
  **10bb1949-d462-4572-9eec-deda51bf9361**. Source `dbdf4ad` plus then-uncommitted
  inputs; source digest
  `8fcad4e1c64aa35a867c27160b8fbefd9c3dcf2042b7939994d8c4add341925c`.
  The dirty source observation is intentional and honest, not a release tag.

Private logs: `.ccoding/r060q-quality-final.log`, `r060q-native.log`,
`r060q-mutation.log`, `r060q-build.log`, `r060q-smoke.log`.

`rtk proxy bin/smoke` passed bundled launch/bootstrap/browser cookie/handoff
replay/origin refusal, heartbeat, graceful quit and listener cleanup. Fresh smoke
data remains at `/private/tmp/ccoding-smoke.177DQC`; post-quit schema seventeen,
SQLite integrity/FKs and released shell lock verified. No user workspace/profile
was copied or started. Implementation `b2eb1cb` fast-forwarded into local main;
feature branch deleted. Only unrelated `Untitled.md.age` remains untracked.
No remote publication or beta-release acceptance is implied by this local merge.
Real-provider throttling/reset/recovery, Cursor classification, newer desktop
runtime conformance, general subprocess checks, physical sleep and signed release
acceptance remain open. No inference, push or publication occurred.
