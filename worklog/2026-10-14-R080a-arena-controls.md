# R080a — Direct agent and Arena controls

Baseline: clean main `2965e36`, 16 commits ahead of origin/main. User requested
per-agent Disconnect/unassignment, reusable connected roles without routine
refresh, modal creation/setup and board + controls, and understandable team copy.
Task acceptance is in `tasks/R080a-arena-controls.md`.

Ponytail full 5.2.0 (MIT), Elixir/LiveView, workflow, security and quality skills
apply. All shell commands use RTK; `rtk proxy` preserves exact code/build output.
No extra frontend framework or dependency. Preserve saved test data/profiles.

Source owners: Foundation profile commands and native account/model checks;
Team/TeamAssignments immutable current teams; AgentsLive/HomeLive roster/wizard;
TabulaLive/PlanningComponent and TeamAdoptionComponent Arena controls.

Distinguish catalog age from failed observations. Native Codex/Cursor task
transports validate the exact model before use; catalog refresh is still needed
for new selections or a failed/invalidated observation. Disconnect is explicit
and must refuse connections retained by active battles or in-flight planning.

## Implementation and verification

- Disconnect uses the existing accepted logout transaction. Current scoped teams
  get append-only unassigned revisions/adoptions, with the default restored last.
  Exact unfinished-battle use, active profile/planning work, expired sessions and
  stale forms refuse changes. Failed logout retains unassignment and history.
- Age alone no longer blocks a saved Agent–Role. Failed/invalidated catalogs still
  block; new selections and optional diagnostics keep the 24-hour gate. Native
  task account/model/config checks remain unchanged. Added Codex Start/Resume,
  planning and Cursor age/failure/model-drift regressions.
- Shared native dialog/hook for planning, repository setup, board/task creation
  and Disconnect confirmation. Specs/ToDo + chooses the correct draft column.
  Plain Board team / Use saved team labels retain version history in Inspect.
- Research: Vibe Kanban Creating Tasks and GitHub Projects Adding items, linked
  from `docs/UI_DASHBOARD.md`. No copied implementation or added dependency.
- `rtk proxy asdf exec mix quality` — 307 tests passed, format/compile,
  Credo clear, Sobelow no vulnerabilities. Existing Sobelow lockfile-parser quoted
  keyword warnings remain. Earlier runs caught outdated UI/freshness assertions
  and a Credo complexity warning; corrected before this passing run.
- `rtk proxy node --test test/dialog_test.mjs` — one passing lifecycle regression:
  repeated open, retained values, server close, focus return, hash/deep-link opening
  under collapsed Advanced and listener cleanup.
- `rtk git diff --check` and local Markdown-link validation — passed.
- Browser: isolated `.ccoding/ui-dev` only; synthetic Arena/task, no real profiles
  or provider calls. Verified modal focus, Escape, brief retention, ToDo + / save
  / modal close, repository and board dialogs, and repository deep link. Narrow
  390×844 dialog has no horizontal overflow; 1440px page stays within its viewport.
  Existing layout/blocked Start copy was inspected, not redesigned in this slice.
- Browser verification found stale release gzip assets masking the new dev hook.
  Development now serves watcher output without gzip; production keeps compression.
  Source smoke checks encoding parity. The deep-link check also caught a dialog
  under closed Advanced; opening now reveals its ancestor disclosures first.
- Native tray automation timed out; requested manual Quit under the repository's
  graceful-restart rule. No force termination of the saved app or provider apps.
  Source preview launchers were stopped through their normal shutdown handlers.
  Retained an online 0600 backup at `.ccoding/r080a-validation/before-rebuild.sqlite3`;
  selected saved DB integrity was OK, foreign keys clear, no battles/pending commands.

- `rtk proxy bin/dev.server --port 0 --no-open --smoke` — passed authenticated
  development shell/session/origin/reload/CSP and new current-asset encoding checks;
  exited cleanly. No preview launcher or listener remains.
- Production asset build is checked separately from replacing the running bundle.
  Native Rust/site sources are unchanged; their suites were not rerun for this slice.

- `rtk proxy env MIX_ENV=prod asdf exec mix assets.deploy` and
  `rtk proxy env MIX_ENV=prod asdf exec mix compile --warnings-as-errors` — passed.
  After adding the explicit transaction assertion, focused TeamAssignments passed
  all eight tests and format check passed. No broader behavior changed after the
  307-test quality run.

## Handoff

Source/UI implementation is verified. Full bundle replacement/smoke and reopening
are pending graceful Quit of the still-running prior bundle. The user was asked
because native tray automation repeatedly timed out; `bin/dev.build` correctly
refuses to overwrite a running bundle. No forced shutdown, migration, personal
profile import, real disconnect or inference occurred. After Quit, run
`rtk proxy bin/dev.build`, `rtk proxy bin/smoke`, and reopen the exact preserved
`/private/tmp/cuckoding-r050c-proof-vvr7u4wp/Open Cuckoding Test.command` launcher.
Verify database/history preservation against the private backup and record the
new listener. Physical/recovery/live-provider release acceptance remains open.
