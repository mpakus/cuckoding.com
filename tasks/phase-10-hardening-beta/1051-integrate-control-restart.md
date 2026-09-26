---
status: in_progress
owner: codex
started_at: 2026-09-25
worklog: worklog/2026-09-25-1051-integrate-control-restart.md
---

# 1051 — Integrate board control and restart the developer app

- [ ] Verify and commit all current board-controller and documentation changes.
- [ ] Integrate into local main without losing existing work.
- [ ] Gracefully stop the owned application and preserve its database/configuration before any forward migration.
- [ ] Build the integrated source, migrate only when required, and restart one verified developer bundle.
- [ ] Record build identity, retained data, health/listener, checks and remaining acceptance limits.
