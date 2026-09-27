---
status: in progress
owner: codex
started_at: 2026-09-27
worklog: worklog/2026-09-27-1052-codex-diagnostic-output.md
---

# 1052 — Preserve Codex results around native diagnostic lines

- [x] Reproduce the reported planning failure with synthetic interleaved Codex diagnostics.
- [x] Share bounded diagnostic handling across structured results, public activity, and usage parsing.
- [x] Keep malformed JSON, unknown output, other providers, capture limits, and diagnostic privacy protected by regression checks.
- [x] Validate the retained failed-run artifact read-only, without starting a provider or changing historical state or importing tasks.
- [x] Update adapter documentation and record focused and quality-gate evidence, including deployment limits.
- [ ] Carry the fix into local main and rebuild/restart the developer app under the existing user authorization, preserving prior run evidence.
