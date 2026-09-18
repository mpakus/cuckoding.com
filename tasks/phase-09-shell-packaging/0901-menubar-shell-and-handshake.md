# 0901 — Menubar Shell and Handshake

## Objective

Implement the production shell per `docs/DESKTOP_SHELL.md`: tray icon with Cuckoding, About, Settings, Quit; Accessory policy; release launch; bootstrap token; READY parsing; single-use `/open` tokens; status polling; termination ladder; crash handling..

```yaml
status: complete
owner: codex
started_at: 2026-09-18
completed_at: 2026-09-18
worklog: worklog/2026-09-18-0901-menubar-shell-handshake.md
```

## Dependencies

- 0003.
- 0101.

## Scope

Implement the production shell per `docs/DESKTOP_SHELL.md`: tray icon with Cuckoding, About, Settings, Quit; Accessory policy; release launch; bootstrap token; READY parsing; single-use `/open` tokens; status polling; termination ladder; crash handling.

## Deliverables

- Shell project and tests.
- Phoenix shell endpoints.

## Checklist

- [x] No dock icon.
- [x] Token never in argv or logs.
- [x] Quit runs hibernate/stop policy first.

## Acceptance criteria

- [x] Clean-machine launch reaches the dashboard.
- [x] Unauthorized access and replay rejected.

## Verification and evidence

The focused shell suite passed 9 Elixir and 4 Rust tests. The local production
build passed its sterile-environment READY, authentication, dashboard, argv,
output, pre/post-READY failure, shutdown, and descendant-cleanup checks. The final native bundle was
arm64 with `LSUIElement=true`, listened only on IPv4 loopback through its BEAM
child, and released the process tree and listener after shell `SIGTERM`.
