---
status: completed
owner: codex
started_at: 2026-09-21
worklog: worklog/2026-09-21-1025-provider-usage-ingestion.md
---

# 1025 — Record provider-reported usage from completed runs

- [x] Delivery and planning sessions persist normalized, idempotent usage from bounded redacted provider output before their stage advances, including a nonzero-exit process.
- [x] Missing or malformed usage never becomes an invented token or cost figure; a capture failure has safe, inspectable evidence.
- [x] Run and Agent Floor views show the provider-reported tokens with cost provenance kept separate.
- [x] Focused parser, accounting, and integration regression checks pass; docs and worklog state the result and limits.
