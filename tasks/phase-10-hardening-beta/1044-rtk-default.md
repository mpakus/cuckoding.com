---
status: in_progress
owner: codex
started_at: 2026-09-24
worklog: worklog/2026-09-24-1044-rtk-default.md
---

# 1044 — RTK by default for managed agents

- [ ] Share verified RTK discovery between plugins and all agent roles.
- [ ] Snapshot audited activation and narrower overrides for new runs.
- [ ] Use command rewriting only when pinned runtime permission, trust and isolation checks pass; show the instructions fallback otherwise.
- [ ] Integrate declared commands after policy validation, preserving execution identity, status and diagnostics without duplicate execution.
- [ ] Confine RTK state, disable duplicate raw logs, and record observed use/exceptions without claiming unmeasured savings.
- [ ] Show effective status and reason in existing LiveView components.
- [ ] Cover discovery, roles, resume, hooks, permissions, quoting, failure and confinement; update docs, build the native app and verify a managed run.

Scope: Cuckoding-managed agents only. No personal configuration changes or runtime upgrades. Preserve the pre-existing edit to `layouts.ex`.
