---
status: in_progress
owner: codex
started_at: 2026-09-24
worklog: worklog/2026-09-24-1045-run-activity.md
---

# 1045 — Readable run activity and failures

- [x] Open with the latest 30 events; load older history automatically with an accessible button and bounded LiveView stream.
- [x] Preserve reading position/history during live refresh; support returning to latest activity.
- [x] Style Plugins consistently with the run's panels and use readable role names.
- [x] Show durable failure evidence independently of feed pagination, including unknown historical causes honestly.
- [x] Explain shell request/completion/failure and RTK observations without exposing raw output or claiming an unreported result.
- [ ] Verify long runs, pagination, refresh/reconnect, redaction and responsive rendering; update docs and worklog.

Automated checks and the native build pass. The remaining acceptance check is
desktop/narrow browser rendering and real viewport-triggered loading after the
user opens a fresh authenticated dashboard; see the worklog for the UI-tool limitation.
