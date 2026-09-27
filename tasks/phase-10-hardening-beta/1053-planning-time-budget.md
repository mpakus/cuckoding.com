---
status: done
owner: codex
started_at: 2026-09-27
completed_at: 2026-09-27
worklog: worklog/2026-09-27-1053-planning-time-budget.md
---

# 1053 — Honor planning time budgets and explain timeouts

- [x] Replace the hard-coded planning deadline with the selected role's saved workflow budget; retain a finite fallback for roles without a matching stage.
- [x] Display the saved planning limit before execution and keep historical run grants unchanged.
- [x] Classify timed-out provider processes independently of exit status, preserve activity, and expose actionable planning/workflow errors.
- [x] Cover the request grant, bounded fallback, timeout classification, and rendered feedback with focused regression tests.
- [x] Update affected documentation, pass quality gates, integrate into local main, and rebuild/restart the owned developer app with data preserved.

Do not start another provider run, edit historical failed-run evidence, import
partial planning messages, or remove existing limits or runtime restrictions.
