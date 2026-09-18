# 0703 — Consolidation Jobs and Redaction

## Objective

Implement idle-time and manual consolidation: merge duplicates, resolve contradictions by supersession, refresh `INDEX.md` within budget, propose expiries, version every rewrite, and resume after crash.

```yaml
status: complete
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0703-knowledge-consolidation.md
```

## Dependencies

- 0702.

## Scope

Implement idle-time and manual consolidation: merge duplicates, resolve contradictions by supersession, refresh `INDEX.md` within budget, propose expiries, version every rewrite, and resume after crash.

## Deliverables

- Consolidation job with progress and resume.
- Idle detection integration with the Power Manager.

## Checklist

- [x] Never runs during an active stage on the same project without user request.
- [x] History kept for superseded items.

## Acceptance criteria

- [x] Contradiction fixtures resolve with both versions retained.
- [x] Job resumes after kill.

## Verification and evidence

Run consolidation fixtures and crash-resume tests.
