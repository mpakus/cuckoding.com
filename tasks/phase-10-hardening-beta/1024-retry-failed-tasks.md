---
status: completed
owner: codex
started_at: 2026-09-21
worklog: worklog/2026-09-21-1024-retry-failed-tasks.md
---

# 1024 — Retry failed tasks without losing run history

- [x] A failed or blocked delivery task offers an accessible Retry action from its task and run pages.
- [x] Retry verifies the prior run is not active, closes a blocked run, and prepares a new run with a distinct branch/worktree while preserving all earlier evidence.
- [x] Duplicate or ineligible requests do not create multiple runs or change active work.
- [x] Errors explain whether the task is Ready, what prevented preparation, and how to continue.
- [x] Focused domain and LiveView regression checks pass; docs and worklog describe the actual behavior and limits.
