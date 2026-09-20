---
status: complete
owner: codex
started_at: 2026-09-20
completed_at: 2026-09-20
worklog: worklog/2026-09-20-1019-shared-login-models.md
---

# 1019 — Reuse provider sign-in across agents and select models

- [x] New agents reuse a compatible saved authorization by default; separate accounts remain explicit.
- [x] Login/check/launch resolve one durable provider profile; missing or incompatible references fail closed.
- [x] Model selection persists through project, board and run snapshots and reaches planning and workflow requests.
- [x] Existing profiles and history survive the additive migration without credential access or copying.
- [x] Document provider-controlled refresh/expiry, verify regression/security/UI checks and record evidence.

No years-long authorization guarantee. Real authenticated refresh/concurrency acceptance remains task 1018.
