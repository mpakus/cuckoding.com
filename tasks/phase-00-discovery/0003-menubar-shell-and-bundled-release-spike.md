# 0003 — Menubar Shell and Bundled Release Spike

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

- [ ] Build the release for macOS arm64 with ERTS.
- [ ] No dock icon; tray menu with Cuckoding, About, Settings, Quit.
- [ ] Reject a browser request without a valid single-use token; reject replay.
- [ ] Parse readiness without scraping arbitrary logs.
- [ ] Handle child crash before and after readiness.
- [ ] Terminate descendants on normal quit and forced quit.
- [ ] Repeat on a clean user account.

## Acceptance criteria

- [ ] The app reaches an authenticated LiveView in the default browser without system Elixir/Erlang.
- [ ] Unauthorized local requests cannot open a session.
- [ ] Quit leaves no child process running.
- [ ] The chosen protocol is documented in an ADR.

## Verification and evidence

Provide a screen recording or timestamped log for startup, rejected access, replayed token, simulated child crash, and clean shutdown.
