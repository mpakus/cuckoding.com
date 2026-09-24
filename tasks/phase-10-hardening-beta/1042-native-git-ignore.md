---
status: complete
owner: codex
started_at: 2026-09-24
worklog: worklog/2026-09-24-1042-native-git-ignore.md
---

# 1042 — Honor host Git ignores in native repository checks

- [x] Honor the user's effective Git ignore file despite the app-owned HOME.
- [x] Preserve repository ignore overrides and reject actual tracked/untracked changes.
- [x] Keep personal Git credentials, hooks and configuration out of execution and agents.
- [x] Cover base capture, worktree preparation/inspection and native-home behavior.
- [x] Document the boundary, pass quality gates, integrate local main and restart
  the verified native build with data preservation and live health evidence.
