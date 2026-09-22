---
status: complete
owner: codex
started_at: 2026-09-22
worklog: worklog/2026-09-22-1029-project-autonomous-dispatch.md
---

# 1029 — Project-level autonomous task dispatch

- [x] Create boards before assigning roles; explicitly apply saved project roles to future runs without rewriting old run snapshots.
- [x] Persist project Start/Pause/Attention/Done, concurrency, and blocker threshold with audit events and safe validation.
- [x] Supervise dispatch of eligible Ready tasks through existing scheduler, preparation, authorization, and workflow; prevent duplicate runs and respect capacity.
- [x] Show project controls, progress, and actionable stop reasons on project, board, and dashboard LiveViews.
- [x] Preserve human completion/release gates, task-proposal review, and trusted-host disclosures.
- [x] Cover persistence, scheduling, failure/restart, UI, and migration; update docs and run quality gates. Signed-app and real-provider acceptance remain release gates.
