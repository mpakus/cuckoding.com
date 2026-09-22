---
status: completed
owner: codex
started_at: 2026-09-21
worklog: worklog/2026-09-21-1026-safe-unexpected-failure-diagnostics.md
---

# 1026 — Locate unexpected workflow failures without exposing exception data

- [x] An unexpected worker exception records a bounded application source location alongside the existing safe failure code, stage, and run correlation.
- [x] The run page shows that location when available and keeps the generic recovery copy for historical events.
- [x] Exception messages, arguments, paths, provider output, and secrets never enter the event or UI.
- [x] Focused regression and repository quality gates pass; docs and worklog distinguish diagnostics from a root-cause fix for historical failures.
