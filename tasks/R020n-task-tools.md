# R020n — Bounded Codex task tools

Status: implementation verified, 2026-10-13; real-account acceptance pending sign-in. Branch: `feature/R020n-task-tools`.

- [x] Run a fresh Codex task session with closed host read/edit tools and no built-in
  shell, network, plugin or delegation tools; exact connection/model binding.
- [x] Enforce owned-root identity, finite calls/bytes/time, protected-policy paths,
  compare-before-write and retained per-call receipts without raw provider logs.
- [x] Reject foreign/duplicate/malformed calls, unexpected tools and late results;
  cancellation stops the process group and never replays writes.
- [x] Add runnable native/transport regressions and verify real protocol preflight.
- [x] Update docs and integrate local main; wire the capability into R050 Start
  before claiming that users can run battles.

The host-tool boundary is D024. No new mandatory setup screen or checkbox wall.

Real-account task acceptance remains open: the approved two-turn test stopped
at `account/read` with `not_connected`; no inference started.
[Evidence](../worklog/2026-10-13-R020n-task-tools.md).
