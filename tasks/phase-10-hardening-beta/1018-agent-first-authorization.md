---
status: in_progress
owner: codex
started_at: 2026-09-19
worklog: worklog/2026-09-19-1018-agent-first-authorization.md
---

# 1018 — Add and authorize agents once, reuse across projects

- [x] Record the agent-first flow, ownership, legacy upgrade, and security contract.
- [x] Obtain an explicit shared app-owned profile decision (2026-09-20).
- [ ] Establish shared-profile reuse for supported runtimes; distinguish real-provider evidence from deterministic checks.
- [x] Provide independent machine-wide Agents management with live authorization status.
- [x] Project setup selects existing agents and roles without asking for credentials again.
- [x] Check distinct agents automatically at start; group multiple roles under the same connection; show reconnect only when necessary.
- [x] Upgrade legacy boards/queued work explicitly without losing tasks/history or rewriting past snapshots.
- [x] Show current project/board/role impact and require confirmation before an audited provider-scoped disconnect.
- [ ] Verify refresh/revocation/restart, concurrent use, two-account separation, secret/path/MCP boundaries, and accessible UI; update documentation with exact evidence.

Contract: [Agent authorization flow](../../docs/AGENT_AUTHORIZATION_FLOW.md).
Do not mark complete from mocked authorization checks alone.
