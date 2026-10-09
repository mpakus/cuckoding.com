# R020f — Fetch the full agent model catalog

Status: complete, 2026-10-08. Branch: `fix/R020f-full-model-catalog`.

- [x] Fetch the agent-provided full model list, including entries hidden from its default picker, across all bounded pages.
- [x] Validate and retain visibility metadata; never invent IDs, infer entitlement or silently substitute a model.
- [x] Preserve older cached rows, stale-cache behavior, grants and model matching; show all returned entries in Agents and Team.
- [x] Cover mixed/hidden pages, malformed flags, pagination bounds and persisted/UI choices with focused regressions.
- [x] Build, refresh the real signed-in catalog without inference, preserve the test profile, update docs/README/AGENTS and merge local main.

Evidence: [worklog](../worklog/2026-10-08-R020f-full-model-catalog.md).

Live-user handoff: the rebuilt app retains the old three-model snapshot until
**Check Codex connection** is submitted. Native read-only verification returned
six; browser use was left to the active user. No model prompt was run.
