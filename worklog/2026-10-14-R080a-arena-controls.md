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

## Packaged completion — 2026-10-15

The user confirmed graceful Quit. Filtered `ps` process identities showed no
remaining repository runtime/BEAM before replacement. The saved DB passed
integrity and foreign-key checks; retained another exclusive 0600 SQLite backup
at `.ccoding/r080a-validation/after-quit.sqlite3` without overwriting the earlier
backup. Menubar-shell and quality-gates guidance applied to packaging verification.

- `rtk proxy env PATH=/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/Users/mpak/.asdf/installs/erlang/28.5/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin bin/dev.build`
  — passed assets, production release and locked Tauri app build. Expected
  OpenSSL relocation signature warnings were followed by replacement signatures.
  No dependency or tracked generated-file changes.
- `rtk proxy bin/smoke` — passed bundled launch, bootstrap, browser cookie,
  handoff replay/origin refusal, heartbeat, graceful quit and listener cleanup.
  Disposable smoke data retained at `/private/tmp/ccoding-smoke.enXe1w`.
- Reopened the unchanged saved launcher
  `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/Open Cuckoding Test.command`.
  At verification, native PID 80158 owned BEAM 80159 and the single loopback
  listener `127.0.0.1:49852`; BEAM cwd was the preserved saved data directory.
  These are dated observations, not stable future launch identities.
- Compared every application table against the after-Quit backup, excluding
  transient browser tokens and checking events separately. All application rows
  were identical: 2 named connections plus the legacy Workspace projection,
  2 Arenas/boards, 2 team revisions, 2 tasks/revisions and 57 commands. All 230
  historical events remained unchanged; only shell/browser authorization events
  were appended. Schema stayed at 11 migrations; integrity OK, no FK errors.
- In the actual reopened Chrome session, verified the saved roster, all
  Disconnect buttons, existing Arena/cards, Create tasks modal, Escape close and
  return focus. No local-read, provider, Disconnect or battle action was run.
  The Arena's existing Speculator/Secutor assignment still points to signed-out
  legacy Codex; connected c2 and Cursor were preserved without substitution.

Implementation is on local main (`90512ea`), with packaging evidence recorded in
this follow-up. No push/deployment, forced shutdown, profile import, real disconnect
or inference occurred. README/AGENTS behavior remains current from that implementation.
Physical/recovery/live-provider and clean-machine release acceptance remains open.
