---
status: done
owner: codex
started_at: 2026-09-24
completed_at: 2026-09-24
worklog: worklog/2026-09-24-1044-rtk-default.md
---

# 1044 — RTK by default for managed agents

- [x] Share verified RTK discovery between plugins and all agent roles.
- [x] Snapshot audited activation and narrower overrides for new runs.
- [x] Use command rewriting only when pinned runtime permission, trust and isolation checks pass; show the instructions fallback otherwise.
- [x] Integrate declared commands after policy validation, preserving execution identity, status and diagnostics without duplicate execution.
- [x] Confine RTK state, disable duplicate raw logs, and record observed use/exceptions without claiming unmeasured savings.
- [x] Show effective status and reason in existing LiveView components.
- [x] Cover discovery, roles, resume, hooks, permissions, quoting, failure and confinement; update docs, build the native app and verify a managed run.

Scope: Cuckoding-managed agents only. No personal configuration changes or runtime upgrades. Preserve the pre-existing edit to `layouts.ex`.

Delivered compatibility fallback: all three pinned agent runtimes use
**Instructions only**. Automatic agent hooks are neither generated nor enabled;
their permission/trust/isolation acceptance remains unverified. Automatic
filtering applies to eligible application-owned captured command output.
Real Codex use and idempotent event import passed; see the worklog for the
installed build and exact distinction from fixture/native-hook acceptance.
