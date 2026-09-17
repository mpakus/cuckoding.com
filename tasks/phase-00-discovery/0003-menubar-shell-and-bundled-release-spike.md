# 0003 — Menubar Shell and Bundled Release Spike

```yaml
status: done
owner: codex
started_at: 2026-09-17
worklog: worklog/2026-09-17-0003-menubar-release-spike.md
```

## Objective

Build disposable spike code for the shell decision in `docs/DESKTOP_SHELL.md`: package a minimal Phoenix release with ERTS inside an `.app`, launch it from a tray-only shell with Accessory activation policy, pass a bootstrap token safely, parse a READY line, open the default browser through a single-use token, poll a status endpoint, and quit through the termination ladder.

## Dependencies

- 0001.

## Scope

Build disposable spike code for the shell decision in `docs/DESKTOP_SHELL.md`: package a minimal Phoenix release with ERTS inside an `.app`, launch it from a tray-only shell with Accessory activation policy, pass a bootstrap token safely, parse a READY line, open the default browser through a single-use token, poll a status endpoint, and quit through the termination ladder. Test without system Erlang/Elixir and without an interactive shell `PATH`. Optionally repeat with the Swift/AppKit shell to compare effort.

## Deliverables

- Reproducible spike and build notes.
- Measured startup/shutdown behavior and failure cases.
- Decision on token handoff, readiness protocol, and shell implementation (confirm or revise ADR-011).
- Issues for signing/notarization (hardened runtime, JIT entitlement, per-binary signing).

## Checklist

- [x] Build the release for macOS arm64 with ERTS.
- [x] No dock icon; tray menu with Cuckoding, About, Settings, Quit.
- [x] Reject a browser request without a valid single-use token; reject replay.
- [x] Parse readiness without scraping arbitrary logs.
- [x] Handle child crash before and after readiness.
- [x] Terminate descendants on normal quit and forced quit.
- [x] Repeat on a clean user account.

## Acceptance criteria

- [x] The app reaches an authenticated LiveView through the default-browser handoff without system Elixir/Erlang.
- [x] Unauthorized local requests cannot open a session.
- [x] Quit leaves no child process running.
- [x] The chosen protocol is documented in ADR-011.

## Verification and evidence

Provide a screen recording or timestamped log for startup, rejected access, replayed token, simulated child crash, and clean shutdown.

Evidence: `spikes/0003-menubar-release/evidence/verification.log`, `spikes/0003-menubar-release/evidence/clean-account-qa.log`, and `docs/MENUBAR_SHELL_SPIKE.md`. The clean-account log records the app running as UID 502 with its bundled ERTS, a loopback-only listener, successful authenticated browser handoff, and no surviving shell or runtime process after quit.
