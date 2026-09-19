---
status: done
owner: codex
started_at: 2026-09-19
worklog: worklog/2026-09-19-1016-live-run-logs.md
---

# 1016 — Live run logs and obvious Ready-task actions

- [x] Run artifacts show a follow-style process-log viewer with at most the latest 5,000 lines and a full filtered-log download.
- [x] Refresh while output grows, survive reconnect/truncation, and bound memory/large lines.
- [x] Resolve files only through run-owned artifact IDs; reject symlinks, traversal, cross-run access, and unauthorized downloads. Never show hidden reasoning or unknown provider payloads.
- [x] Ready cards explain manual start and link to task setup; queued tasks link to the prepared run without starting duplicate work.
- [x] Focused regression tests, formatter/compiler/static checks, and docs/worklog evidence pass.
