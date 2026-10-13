# R020n — Bounded Codex task tools

Status: implementation verified, 2026-10-13; one real-account synthetic read/edit verified; broader acceptance remains open. Branch: `feature/R020n-task-tools`.

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

Broader real-account task acceptance remains open. R020o fixed Code Mode routing
and clarified the host-service grant. A separately authorized c2/GPT-6.1 Sol
synthetic read/edit turn passed with exact bytes and verified normal cleanup.
See [current evidence](../worklog/2026-10-13-R020o-task-tool-routing.md).
[Evidence](../worklog/2026-10-13-R020n-task-tools.md).
