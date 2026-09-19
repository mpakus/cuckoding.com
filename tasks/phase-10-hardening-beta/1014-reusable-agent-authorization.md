---
status: completed
owner: codex
started_at: 2026-09-19
completed_at: 2026-09-19
worklog: worklog/2026-09-19-1014-reusable-agent-authorization.md
---

# 1014 — Reusable agent authorization

## Goal

Save machine-local agents once, reuse them across projects, and reuse supported provider authorization without sharing project session state.

## Acceptance criteria

- [x] Saving an agent creates or updates one global provider-account record and keeps a stable reference in the immutable project configuration.
- [x] Another project can attach a saved global agent without re-entering its runtime information.
- [x] Codex authorization uses the macOS Keychain once while every run keeps its own `CODEX_HOME`, configuration, history, and generated instructions.
- [x] Claude helper configuration remains reusable; Cursor authentication remains run-scoped until credential-only reuse passes isolation verification.
- [x] No credential value is stored in SQLite, project configuration, events, logs, or browser HTML.
- [x] Existing board and run snapshots remain unchanged.
- [x] Focused tests and project quality gates pass.
