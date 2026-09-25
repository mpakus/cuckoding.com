---
status: in_progress
owner: codex
started_at: 2026-09-24
worklog: worklog/2026-09-24-1046-edit-stopped-tasks.md
---

# 1046 — Edit task details after a stopped run

- [x] Allow manual edits after a failed/stopped delivery run when no work can still consume changing task inputs.
- [x] Preserve failed-run evidence and ensure a new retry uses saved changes.
- [x] Reject retries with unsaved changes and preserve entered text during refresh/errors.
- [x] Explain the edit/save/retry path and how the assigned Speculator helps on a new run.
- [ ] Cover domain, LiveView, audit and retry behavior; update docs, rebuild and verify.
