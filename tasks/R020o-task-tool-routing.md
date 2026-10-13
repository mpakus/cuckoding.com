# R020o — Codex task-tool routing

Status: routing implemented and locally verified 2026-10-13; real write acceptance pending. Branch: `fix/R020o-task-tool-routing`.

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

The approved write fixture was exercised and read successfully, but returned a
blocked report before editing. The clarified host-grant wording awaits one more
explicitly authorized real write test. This is an open acceptance gate, not a
passed write result. Start remains disabled.
