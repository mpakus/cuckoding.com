# 0901 — Menubar Shell and Handshake

## Objective

Implement the production shell per `docs/DESKTOP_SHELL.md`: tray icon with Cuckoding, About, Settings, Quit; Accessory policy; release launch; bootstrap token; READY parsing; single-use `/open` tokens; status polling; termination ladder; crash handling..

## Dependencies

- 0003.
- 0101.

## Scope

Implement the production shell per `docs/DESKTOP_SHELL.md`: tray icon with Cuckoding, About, Settings, Quit; Accessory policy; release launch; bootstrap token; READY parsing; single-use `/open` tokens; status polling; termination ladder; crash handling.

## Deliverables

- Shell project and tests.
- Phoenix shell endpoints.

## Checklist

- [ ] No dock icon.
- [ ] Token never in argv or logs.
- [ ] Quit runs hibernate/stop policy first.

## Acceptance criteria

- [ ] Clean-machine launch reaches the dashboard.
- [ ] Unauthorized access and replay rejected.

## Verification and evidence

Run shell tests and the clean-machine launch test.
