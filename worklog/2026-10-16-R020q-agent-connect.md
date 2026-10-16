# R020q — Agent connection simplification

Claimed 2026-10-16 from clean main 54bcfed (35 ahead of origin/main).
Acceptance: signed-in-only Refresh; one-gesture browser authorization with the
existing protected transient redirect; default editable names and metadata-only
Cursor path discovery; preserved session/form/revision/permission boundaries.

Ponytail full 5.2.0 (MIT), local LiveView/adapter/security/quality instructions.
RTK proxy preserves exact source/protocol and test/build evidence. No subagents.

Root causes: step 2 renders Refresh even when signed out and renders its login
handoff separately below the wizard. Source `bin/dev.server` omits the native
shell's CCODING_DISCOVERY_HOME hint, so discovery searches private runtime HOME
instead of known host CLI locations. The selected provider's name starts blank.
The user's Cursor CLI exists at ~/.local/bin/cursor-agent / agent symlinks.

Use a small browser-behavior hook; login initiation remains guarded in LiveView
and the domain ledger. The existing local redirect remains the only place that
reads the transient provider URL. Metadata discovery never launches a CLI or
imports a personal profile. No controller/provider protocol or execution permission
changed; pending-tab ownership is transient browser behavior, not new authority.

Delivered: signed-in-only Refresh; one in-place Sign in / Continue control;
AgentLogin preopens a user-gesture tab, detaches its opener and follows only the
exact consented command's existing local redirect once ready. Invalid forms,
cancellation/unmount close the pending tab; blocked/closed tabs and reconnects
retain the manual local link without replay. Provider URLs stay in existing
transient server storage and the protected controller redirect. New names default
to Codex/Cursor, follow provider changes only while untouched, and remain editable.
Cursor gets the discovery path; missing paths give visible guidance and disable
Continue instead of triggering hidden-input browser validation. Explicit manual
overrides and all domain guards remain.

Verification:
- `rtk proxy env PATH=<pinned> mix test
  test/cuckoding_web/foundation_live_test.exs
  test/cuckoding_web/agents_live_test.exs`: 27 passed. Includes default Cursor name /
  installed-path discovery without execution, custom input retention, exact
  named-agent login, signed-in-only refresh, stale-form rejection, model choices,
  cancellation/reconnect, protected redirects and provider URL canaries.
- `rtk proxy node --test test/agent_login_test.mjs test/dialog_test.mjs`: 4 passed.
  Covers one handoff only, detached opener, foreign command/route refusal, rejected
  and cancelled forms, listener cleanup, blocked/closed tabs and no reconnect replay.
- `rtk proxy env PATH=<pinned> mix quality`: 370 passed; format, compile with
  warnings as errors, Credo strict, Sobelow and dependency audit passed. Existing
  Sobelow lockfile quoted-keyword parsing warnings remain. Rust code unchanged;
  its full suite was not rerun or claimed as new evidence.
- Isolated in-app browser synthetic fixture on 127.0.0.1:54759: one actual click
  opened exactly one second tab and reached only the matching local redirect.
  The resulting page visibly reported Opener disabled. No provider/account URL
  was visited. Both test tabs and the owned fixture server were closed.
- `rtk proxy env PATH=<pinned> bin/dev.build`: passed; assembled production release,
  asset bundle and native app. Existing OpenSSL relocation/ad-hoc signing notices
  remain, not release signing/notarization evidence.
- `rtk proxy bin/smoke`: passed in `/private/tmp/ccoding-smoke.joJwKQ`, covering
  bundled handshake, cookie, canonical routes, replay/origin refusal, heartbeat,
  graceful Quit and listener cleanup.
- `rtk proxy env PATH=<pinned> bin/dev.server --smoke --port 0`: passed at 55067;
  session, reload, origin, strict CSP/no Tidewave and normal owned cleanup.
  No personal profile import or provider use. Launcher syntax and 182 local
  Markdown file references validated; whitespace checks passed.

Pinned PATH:
`/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/opt/homebrew/opt/erlang/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`.

Restart/data preservation:
- Verified idle native 77635/backend 77636, exact executable/parent/start (Thu
  Oct15 23:53:13), cwd and loopback listener. Integrity/FKs passed, no active
  setup commands or resource-holding battles. Exclusive 0600 online backup:
  `.ccoding/r020q-validation/before-rebuild.sqlite3` with 259 prior events.
- Tray remains unusable as observed earlier in this session. Used Development's
  documented audit-token-bound normal backend SIGTERM fallback, after a final
  idle transaction/identity check. Both owned processes exited and listener 53635
  closed; no escalation/unrelated process signal. No tray Quit event is implied.
- Reopened the unchanged saved `Open Cuckoding Test.command` and data selection.
  Native 83643/backend 83645 started Fri Oct16 00:12:56 2026; loopback 55149.
  All 14 state tables and 259 prior events match backup exactly; only three normal
  startup events were added. All 73 assembled/bundled application ebin files match.
  DB integrity/FKs pass. Saved connections/models/roles/tasks/profiles are intact.
- Packaged Home/Agents rendered with existing named connections. Additional
  interactive wizard visual actions were interrupted by concurrent user control;
  default/path/login surfaces are covered by the runnable LiveView checks, and
  popup behavior has the independent actual-browser fixture evidence above.

No real provider reauthorization or inference was performed. Live-account OAuth,
complete timed onboarding and remaining beta acceptance stay open. Implementation
`3da9c8b` fast-forward merged to local `main`; merged branch
`fix/R020q-agent-connect` deleted. Docs, AGENTS and README are updated. No remote
push/publication. The verified saved-workspace app stays running on 55149.
