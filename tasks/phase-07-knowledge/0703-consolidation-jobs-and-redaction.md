# 0703 — Consolidation Jobs and Redaction

## Objective

Implement idle-time and manual consolidation: merge duplicates, resolve contradictions by supersession, refresh `INDEX.md` within budget, propose expiries, version every rewrite, and resume after crash..

## Dependencies

- 0702.

## Scope

Implement idle-time and manual consolidation: merge duplicates, resolve contradictions by supersession, refresh `INDEX.md` within budget, propose expiries, version every rewrite, and resume after crash.

## Deliverables

- Consolidation job with progress and resume.
- Idle detection integration with the Power Manager.

## Checklist

- [ ] Never runs during an active stage on the same project without user request.
- [ ] History kept for superseded items.

## Acceptance criteria

- [ ] Contradiction fixtures resolve with both versions retained.
- [ ] Job resumes after kill.

## Verification and evidence

Run consolidation fixtures and crash-resume tests.
