# R080g — Dashboard and activity

Claimed on local main 23b83d4 after the R070a merge/branch deletion. Untitled.md.age
untouched. Ponytail full 5.3.2 (MIT), OTP/LiveView, workflow, architecture, quality
and installed frontend/incremental/testing/review guidance apply. RTK proxy for
exact source/verification output; pinned Elixir/OTP PATH. No provider invocation.

Design contract: keep the existing black/green tokens, welcome journey and a
single operational region. Show actual saved claims, exact bindings and task
progress; direct board links are the primary operational action. Twenty-row
pages and explicit live/reading mode keep logs bounded and stable. No new
animation, branding/assets, provider controls, grants or dependency.

Delivered: bounded Dashboard query projections, global worker/last-battle progress
and direct board links, with 20-row Arena pages. Shared ActivityComponent shows
chronological metadata-only event pages globally/per Arena with Older/Newer and
Pause/Follow latest. Direct Arena scope wins over board/command references, so
planning/card events remain visible without foreign-scope fallback. Both stateful
components guard their own session. Reading mode, disclosures and dirty drafts
survive live patches; the tiny ActivityFollow hook moves only a following list.
Existing Agents, Team and Start surfaces/authority remain unchanged.

The thirteenth/fourteenth migrations add only observation indexes. The fourteenth
is separate because the source preview had already applied thirteen before the
board/command scope inspection; no observed migration was rewritten. Prior eleven-
migration backup/upgrade regression now verifies all three new index migrations
through fourteen, retained facts, integrity/FKs and query plans.

Verification (pinned Elixir/OTP via RTK proxy):
- New Dashboard regressions failed before implementation, then passed.
- `mix quality`: 408 tests pass; format/compile/Credo clean, Sobelow no
  vulnerabilities, dependency audit exit 0. Existing Sobelow lockfile warnings
  persist; migration module reload can warn inside the isolated migration test.
- Last public requested-model label change: five focused dashboard LiveView tests
  passed. No execution logic changed after the full suite.
- `node --test test/dialog_test.mjs test/agent_login_test.mjs test/activity_follow_test.mjs`:
  five passed. `mix assets.build`: passed.
- Mutation inverted whether Arena scope is applied; the scoped chronological
  activity test failed on foreign event kinds. Source restored and full quality
  rerun. Metadata-only worker/event DTOs exclude canary private payloads.
- CUA Chrome source preview on loopback port 55875: desktop dashboard and 320px/
  768px rendering observed; Older/Follow by mouse, Tab→Return pagination,
  direct board link and scoped Arena activity verified. No provider was launched.
  Console showed extension messages and no application error; Chrome reported
  existing form autofill/id improvements outside these new non-form components.
  Exact 1024/1440 viewport and computed-font/text-spacing/axe verification were
  not established; full responsive/accessibility acceptance stays open.
- Source preview used the existing separate `.ccoding/ui-dev` data, no reset or
  fixture injection. Its owned Python lock/executable/start/cwd were verified;
  normal SIGTERM completed its shell-quit cleanup and closed port 55875. The
  saved native test workspace was not rebuilt/replaced by this UI validation.

Review: observations never mutate authority; page size, scope precedence,
session guards and safe public projections checked. No raw log-file opening,
real-provider concurrency or unfamiliar-user ten-minute timing claim.
