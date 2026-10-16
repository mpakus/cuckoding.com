# R020q — Single-action sign-in and discovered agent defaults

Status: implemented and locally verified, 2026-10-16. Local integration pending.

- [x] Show Refresh connection only for a signed-in agent. Keep refresh/model
  freshness, exact-connection and existing native setup gates unchanged.
- [x] One sign-in click opens a blank tab during the user gesture, then hands
  that tab to the existing session-protected redirect when the exact consented
  login command supplies a validated URL. Keep one in-place fallback control for
  blocked/closed tabs and reconnects. No raw provider URLs in browser assigns,
  SQLite or logs; rejected forms cannot launch native login.
- [x] Prefill an editable provider name and discover Cursor's installed CLI by
  metadata. Preserve custom names/paths. Source UI passes the same discovery-only
  host-home hint as the native shell; provider environments/grants stay unchanged.
- [x] Add focused LiveView/browser-hook checks, update docs/AGENTS/README, run
  quality/build/smoke and safely preserve/reopen the saved workspace.
- [ ] Merge this verified slice into local main and remove its merged branch.

No model usage, native runtime permission expansion or credential/profile import.
The synthetic browser check proves popup behavior, not a new live-provider OAuth
acceptance. Interactive wizard visual inspection was interrupted by user control.

[Worklog](../worklog/2026-10-16-R020q-agent-connect.md).
