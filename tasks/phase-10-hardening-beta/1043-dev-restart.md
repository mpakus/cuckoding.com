---
status: complete
owner: codex
started_at: 2026-09-24
worklog: worklog/2026-09-24-1043-dev-restart.md
---

# 1043 — Developer app restart command

- [x] Add executable `bin/dev.restart` for this checkout's existing native bundle.
- [x] Gracefully stop only the verified development shell; wait for its process
  tree to exit and refuse unrelated instances or incomplete cleanup.
- [x] Launch once and verify the new shell, release child and loopback health.
- [x] Document build/restart usage and add focused runnable regression checks.
- [x] Record checks and delivery state without modifying native user data.
