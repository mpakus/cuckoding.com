# R010 — Local application foundation

Status: complete, 2026-10-06; verified for local main integration.
Depends on R001 (`b6523ce`, integrated into local main).

## Acceptance

- [x] Pin compatible Elixir/OTP, Phoenix/LiveView, Ecto/SQLite and Tauri 2 tooling;
  retain the project's Apache-2.0 license.
- [x] Create a minimal Phoenix application with SQLite migrations, an idempotent
  command/event boundary and a supervised durable dispatcher; isolate rebuild data.
- [x] Provide a thin tray application with Open CCoding, Settings, About and Quit,
  launching the bundled release and a minimal browser screen.
- [x] Require one-time shell bootstrap/browser handoff, expire authenticated
  sessions, validate host/origin/CSRF and verify owned shutdown.
- [x] Detect runtime/RTK executables by metadata only; expose Ponytail full and
  RTK defaults without implying providers are authorized or runnable.
- [x] Verify formatting, compilation, focused tests, static/security analysis,
  native tests/build, real loopback/browser reconnect and tray shutdown.
- [x] Update docs and AGENTS where needed, then commit and merge into local main.

Scope excludes provider authorization/execution (R020), boards and battles.

Verified: 22 ExUnit tests, 4 Rust tests, static/security checks, repeat bundled
build and real HTTP smoke. The final bundle opens the authenticated browser;
setup/recheck, disclosure retention, reload, keyboard and 390px layout passed.
Owned shell-loss cleanup passed. The tray Quit handler is covered by the native
protocol smoke; a physical menu click was not observed because computer use
cannot attach to the windowless tray app. Public release/clean-machine and
physical sleep acceptance remain R100/R060, not foundation claims.
