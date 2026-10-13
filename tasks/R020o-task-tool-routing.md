# R020o — Codex task-tool routing

Status: routing and one real synthetic read/edit verified 2026-10-13. Initial
branch: `fix/R020o-task-tool-routing`; evidence follow-up: `fix/R020o-write-acceptance`.

The approved read fixture reached GPT-6.1 Sol but returned blocked because Code
Mode's host was disabled. Restore the runtime's routing layer without enabling
shell, imports, filesystem/network APIs or arbitrary host tools.

- [x] Enable and validate Code Mode/host only for bounded task turns; keep
  diagnostics and planning in their existing no-tools profile.
- [x] Use the current typed dynamic-function contract and reject unsupported
  calls/configuration. Preserve exact model, profile, path and cleanup boundaries.
- [x] Exercise the remaining approved write fixture alone, within five minutes;
  do not replay the already consumed read turn or infer broad release acceptance.
- [x] Run regressions, update docs/AGENTS/README, rebuild the selected local app,
  commit and merge into local main. No push or deployment.

[Evidence](../worklog/2026-10-13-R020o-task-tool-routing.md).

The first approved write fixture read successfully but returned blocked before
editing. After clarifying the host grant, the user authorized one additional
five-minute test. It passed in 10.88 seconds with exact read/edit hashes and final
bytes. Codex and its separate Code Mode process both exited; all 11 durable app
tables were unchanged. No Arena or personal profile was accessed.

Full battle, independent review and crash/sleep acceptance remain open. Start
remains disabled. This evidence update changes no product code or permissions.
