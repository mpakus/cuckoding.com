# R080b worklog · 2026-10-15

Claim: `tasks/R080b-disconnect-runtime-drift.md` on
`fix/R080b-disconnect-runtime-drift`, from clean main `587ea2b` (31 ahead).

Acceptance: a confirmed exact-agent Disconnect remains useful when its executable
has changed. Deactivate the local connection and unassign current roles without
launching the changed program, preserving native profile/history/other agents.
Keep battle, busy, revision, session and form guards, stable command replay and
honest native-logout versus local-only results.

Ponytail full 5.2.0 (MIT), Elixir/LiveView, security-review, architecture,
menubar-shell and quality-gates. `rtk proxy` keeps exact source/protocol and
test/build evidence. No new dependencies, provider inference or silent fallback.

Root cause: the current saved workspace has no pending setup and no logout command
for the failed click. `Foundation.profile_command/5` returns `:version_required`
before enqueue when `verified_executable/1` finds drift. Legacy Codex's recorded
inode is 385698424; its current executable is inode 387671844. Path/size remain
the same. No executable was run to diagnose this. AgentsLive hides this error
behind its generic busy/change message. c2/Cursor remain separate connections.

Implemented `Foundation.disconnect_agent/4`: replay exact prior Disconnect/logout
receipts first; otherwise use existing verified native logout or completed
`local-disconnect-v1`. The local branch shares command transaction/rejections,
TeamAssignments and projection invalidation; it records authorization Unknown,
provider logout Not attempted and consumes a workspace revision. No native task
is enqueued. Roster closes the modal, explains local-only completion and disables
the already disconnected button. Native logout code/permissions are unchanged.

Verification:
- Focused `rtk proxy env PATH=<pinned> mix test
  test/cuckoding/team_assignments_test.exs
  test/cuckoding_web/agents_live_test.exs test/cuckoding/battles_test.exs`:
  84 passed before the additional atomic audit rollback test.
- `rtk proxy env PATH=<pinned> mix quality`: 367 passed, format/compile with
  warnings as errors, Credo strict, Sobelow and dependency audit passed. Initial
  Credo identified nested/complex generic enqueue code; moved the SQLite-only
  command into its own existing-style clause. No suppressions added. Existing
  quoted-keyword lockfile warnings from Sobelow remain; no vulnerabilities.
- Regressions cover actual fixture executable replacement/removal, signed-out
  and connected projections, exact-scope unassignment, other connection/history
  preservation, replay after runtime re-verification, invalid/recovered/expired
  forms, stale/busy/running/paused battle refusal, event-trigger rollback and
  reconnectable Disconnected status. No provider inference/credentials accessed.

Pinned PATH:
`/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/opt/homebrew/opt/erlang/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`.
Rust sources are unchanged; no repeat claim of the earlier Rust suite.

Rebuild: tray CUA call still timed out. Used Development's authorized idle-only
normal shutdown fallback: exact native 56624/backend 56625, parent/start identity
(Thu Oct15 22:15:50 2026), executable/data cwd and loopback listener verified.
Integrity/FKs passed, no active commands or resource-holding battles. Exclusive
0600 online backup `.ccoding/r080b-validation/before-rebuild.sqlite3` retains
249 events. Audit-token-bound SIGTERM caused normal backend and shell exits,
listener 62980 closed, no escalation. Saved launcher/data selection preserved.
This fallback does not emit the tray Quit event.

Build/runtime acceptance:
- `rtk proxy env PATH=<pinned> bin/dev.build`: passed; production Elixir and
  packaged native app rebuilt. Existing OpenSSL relocation notices were followed
  by existing ad-hoc signing; no release-signing/clean-machine claim.
- `rtk proxy bin/smoke`: passed in `/private/tmp/ccoding-smoke.ZA3Yt1`.
  Packaged native `--smoke-test` against assembled `_build/prod/rel/cuckoding`
  also passed in `/private/tmp/ccoding-r080b-source-w50uoqgb`. Both cover launch,
  bootstrap, protected routes, browser cookie, replay/origin refusal, heartbeat,
  normal Quit and listener cleanup. No account/inference calls.
- Reopened the exact saved launcher/data root: native 65744/backend 65750,
  started Thu Oct15 22:54:26 2026, loopback `127.0.0.1:49384`. Before UI action,
  all 14 saved tables and 249 prior events matched the backup; only normal
  shell/browser/power observations were added. All 73 assembled application
  ebin files match the bundled release; integrity/FKs pass.
- Native Chrome UI: opened Agents → Disconnect Codex → Disconnect and unassign.
  The modal closes, the roster says Disconnected locally / provider sign-out Not
  attempted, and Codex's button becomes disabled/Disconnected. Screenshot:
  `.ccoding/r080b-validation/disconnected.png` (private, ignored artifact).
- Post-action audit: exactly one completed `disconnect_agent` local-only receipt
  and three completed causal role-unassignment commands; no native/provider work
  queued. Workspace revision increments once; all existing command/team/event
  rows stay byte-identical. Only the selected legacy Codex projection and its
  current scoped roles change. Cursor/c2 records, existing c2 default-role
  assignments, Arena/board creation records, tasks and all history remain intact.
  No profile files were accessed by the local command. Integrity/FKs pass.
- Local Markdown references in all 12 changed instruction/docs/task/worklog
  files resolve; whitespace checks pass. No Rust source change, provider inference,
  physical sleep or clean-machine/release acceptance was exercised in this fix.

Implementation `37550bb` fast-forward merged to local `main`; merged branch
`fix/R080b-disconnect-runtime-drift` deleted. Instructions, README and affected
docs are updated. No remote push/publication or inference. The rebuilt app stays
running at `127.0.0.1:49384`, with the requested Codex local disconnect completed
and all unrelated connections/assignments retained.
