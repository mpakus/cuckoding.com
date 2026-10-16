# R080c — Fast, polished setup-to-Start flow

Claimed 2026-10-15. Acceptance: the five-step user journey, saved-state Home,
immediately visible role bindings, compact Arena controls, explicit board-team
review, responsive black/green polish and unchanged authorization boundaries.

Baseline: clean local main at d064f3d, 33 commits ahead of origin/main. Previous
implementation evidence is historical. Read root instructions, product,
architecture, data, flow, security, execution and UI contract; inspected the
actual Home/Agents/Team/Arena/planning/battle callers and focused tests.
Ponytail full 5.2.0 (MIT), local LiveView/workflow/quality skills and better-ui /
better-layout apply. RTK proxy is used for exact source, test and protocol output.

Findings: Home always resets its displayed journey to Agents; role bindings are
hidden behind four disclosures; Arena repeats long authority text above the
board and hides team adoption in Advanced. No domain/permission expansion is
needed. Preserve SQLite authority, named identities, consent, stale-form guards,
independent review and all saved data. No provider inference is included.

Implemented read-only Home next-action projections; shared function components for
the journey and saved Arena links; directly visible per-role bindings and optional
role details; direct Board team dialog with existing explicit adoption; compact
Start authority and on-demand limits; exact-connection/status grouped blockers.
Known setup blockers disable Start rather than offering a second readiness mode.
The domain still rejects forged submissions. Full task/check scope, consent,
independent review, error/cleanup evidence and current control handlers are retained.
No new DB state, provider job, migration, dependency or privilege is introduced;
presentation-only changes use existing audited domain operations, not new events.

Polish: wider useful board area, restrained green surface gradients, clearer
spacing/role cards, contrast-checked form borders, visible focus, native scroll
containment and reduced-motion gated press feedback. Narrow CSS uses one card
column and horizontal non-wrapping navigation; live narrow rendering is not verified.

Verification (pinned PATH below):
- `rtk proxy env PATH=<pinned> mix test test/cuckoding_web/foundation_live_test.exs
  test/cuckoding_web/team_live_test.exs test/cuckoding_web/arena_live_test.exs
  test/cuckoding_web/battle_live_test.exs
  test/cuckoding_web/team_adoption_live_test.exs`: 55 passed.
- Final `rtk proxy env PATH=<pinned> mix quality`: 368 passed; formatter, warning-
  as-error compilation, Credo strict, Sobelow and dependency audit passed.
  Existing Sobelow quoted-keyword lockfile parsing warnings remain. Initial
  test failures identified obsolete UI-location expectations and a missing parent
  assign for live default-team comparison; fixed without weakening domain gates.
  A subsequent formatter-only failure after adding the agent-name text-input type
  was corrected before the final quality/build runs.
- Regressions cover Home saved progress, reconnect, exact default-role preservation,
  no implicit board adoption or provider/battle launch, visible choices, dirty text,
  modal adoption, stale/expired forms, blocker grouping and forged disabled-Start
  refusal. Existing battle controls and every other app test remain green.
- `rtk proxy env PATH=<pinned> bin/dev.server --port 0`: source UI at 52293,
  real bootstrap/session/LiveReload. Desktop Chrome Team visually inspected:
  four visible binding cards, shared journey, green focus/actions and optional
  role details. User's original wizard tab was preserved by using another tab.
  Subsequent narrow/packaged UI actions were interrupted by concurrent browser
  control; no claim of completed responsive or full interactive acceptance.
- All 178 local Markdown file references in changed instruction/docs/task/worklog
  files resolved. Form border contrast is 3.31:1 on #050807 and 3.14:1 on #0b110e.
- `rtk proxy env PATH=<pinned> bin/dev.build`: final formatted-source production
  release and native bundle passed. Existing OpenSSL relocation/ad-hoc re-signing
  notices remain. Rust sources unchanged; no repeat claim of the native full suite.
- Final `rtk proxy bin/smoke`: passed in `/private/tmp/ccoding-smoke.ACth1s`:
  packaged bootstrap, browser cookie, protected routes, replay/origin refusal,
  heartbeat, graceful Quit and listener cleanup. No provider inference.

Pinned PATH:
`/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/opt/homebrew/opt/erlang/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`.

Restart/preservation:
- Confirmed native 65744 / backend 65750, exact parent/start/executable, saved
  data-root cwd and loopback 49384; no active commands or resource-holding battles.
  SQLite integrity/FKs passed; exclusive 0600 online backup at
  `.ccoding/r080c-validation/before-rebuild.sqlite3` retains 256 prior events.
- Tray control timed out again. Used Development's documented idle-only normal
  shutdown via backend audit-token-bound SIGTERM. A first throwaway Python helper
  faulted before signalling: `mach_task_self_` is an SDK global, not a function.
  All owned app processes were reverified unchanged, SDK declarations inspected,
  then the corrected helper used the global port. Backend and native shell exited
  normally. The separately owned source launcher 74451 was also stopped normally
  after its idle check; both listeners closed, no escalation/unrelated signals.
  This fallback does not emit the tray `shell.quit_requested` event.
- Reopened the exact saved `Open Cuckoding Test.command` without changing its
  `CCODING_DATA_DIR`. Current native 77635 / backend 77636 started Thu Oct15
  23:53:13 2026, listener `127.0.0.1:53635`, saved data root unchanged.
- All 14 non-session/state tables and all 256 prior events match backup exactly;
  only three normal startup events were added. All 73 assembled/bundled application
  ebin files match. DB integrity/FKs pass. No roles, model selections, projects,
  boards, tasks or profiles were changed by the UI audit/rebuild.

Open: narrow/package interactive walkthrough, timed ten-minute onboarding, actual
planning/battle provider allowance acceptance, physical recovery and release gates.
Implementation `a713383` fast-forward merged to local `main`; merged branch
`feature/R080c-fast-simple-flow` deleted. Docs, AGENTS and README are updated.
No push/publication. The saved-workspace native app remains running at 53635;
the source preview was stopped with its data retained. Narrow/package interactive
and timed acceptance remain explicitly open rather than inferred from tests.
