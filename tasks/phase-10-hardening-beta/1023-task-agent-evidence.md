---
status: complete
owner: codex
started_at: 2026-09-21
worklog: worklog/2026-09-21-1023-task-agent-evidence.md
---

# 1023 — Recover Development startup and show agent work on its task

- [x] Explain run `01a0bcd7-0e7d-7df7-8263-a71361f5de57` from durable evidence and fix the root cause without rewriting that run.
- [x] Saved Cursor can launch with its fixed non-secret file-store selector; failures retain a safe, useful code instead of collapsing to an unexpected failure.
- [x] When RTK is installed, every launched agent receives an explicit command instruction and usable binary path; absence remains a labeled fallback and never blocks work.
- [x] Persist public agent messages and the actual specification as task-linked evidence, and show them on the task page across reloads.
- [x] Cover the behavior with focused security, workflow, and LiveView checks; update docs and worklog with honest limits.
