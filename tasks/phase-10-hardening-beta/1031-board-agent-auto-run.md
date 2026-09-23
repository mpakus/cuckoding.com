---
status: complete
owner: codex
started_at: 2026-09-22
worklog: worklog/2026-09-22-1031-board-agent-auto-run.md
---

# 1031 — Board agents without per-run selection

- [x] Applying saved project roles to a board assigns those agents to future runs and adds audited bindings to compatible queued runs on that board.
- [x] Running and historical run snapshots remain immutable; incompatible queued roles fail without partial updates.
- [x] The run page directs missing assignments back to the board/project assignment instead of making per-run selection the normal workflow.
- [x] Project Start continues to dispatch all eligible Ready tasks automatically and rechecks saved-agent authorization before provider work.
- [x] Focused domain and LiveView regressions cover the queued-run upgrade and UI guidance; affected docs and quality evidence are updated.
