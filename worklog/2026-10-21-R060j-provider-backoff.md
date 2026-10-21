# R060j — Automatic backoff

Claimed 2026-10-21. Baseline local main 655e8f7; 43 ahead of origin/main.
Unrelated untracked Untitled.md.age left untouched. Ponytail full 5.3.2 (MIT),
local architecture/workflow/LiveView/security/quality skills, installed incremental
implementation, testing and review guidance. Existing immutable retry receipts,
exact bindings and finite budgets remain authoritative. No native grant/schema
change or provider usage. RTK proxy preserves exact source and verification output.

Plan: freeze automatic-provider-backoff-v1 in new Starts; schedule only failures
already eligible for R060b. Reuse the existing retry transition at due admission,
never replay an attempt. Cancel scheduled retry on explicit request or restart;
historical battles keep their manual contract. Tests precede implementation.

Delivered: new snapshots freeze `automatic-provider-backoff-v1`. Only normalized
connection_lost/profile_busy/timeout/launch_failed failures already eligible for
R060b schedule a 5/20-second SQLite wait inside the existing two retries. Due
admission revalidates exact attempt/bindings and original limits in the claim
transaction, then records Retry and claims a fresh attempt. Failed writers retain
fresh preparation/coordinator/Speculator and all failed edits. Generic provider
errors stay manual. Cancel/Stop/Skip/timing fences clear the wait; startup cancels
automatic admission without replay. The LiveComponent exposes wait/countdown,
exact role/runtime/model and guarded cancellation without losing dirty drafts.

Verification (pinned Elixir 1.20.3/OTP28 PATH through RTK proxy):
- Initial new backoff regression failed against the baseline's missing policy.
- Focused domain/executor/LiveView suite: 134 passed, including concurrent due
  claims, no worker during wait, real five-second dispatch, writer/final budgets,
  stale/recovered/expired-session cancellation, restart, changed bindings, backward
  time, malformed metadata, caps and review/native/cleanup exclusions.
- Mutation: inverted pending-state predicate; the before-due claim test failed
  (`not_running` instead of `backoff`). Original source restored and reverified.
- `mix quality`: 388 tests passed; format/compile/Credo clean; Sobelow no
  vulnerabilities; dependency audit exits 0. Existing quoted-keyword warnings
  from the lockfile/Sobelow parser persist, no compiler warnings added.
- `node --test test/dialog_test.mjs test/agent_login_test.mjs`: four passed.
- `git diff --check`: passed. Source review checked authority, concurrency,
  cancellation, no sleeping workers and no new native/provider grants/dependencies.

No provider invocation, physical sleep drill, native bundle replacement or manual
browser walkthrough was performed for this slice. Full beta gates remain in PLAN.
