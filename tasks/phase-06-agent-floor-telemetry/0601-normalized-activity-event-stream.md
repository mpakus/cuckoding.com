# 0601 — Normalized Activity Event Stream

## Objective

Persist and broadcast normalized public activity events with the full correlation chain, redaction, sequence numbers, reconnect catch-up, and stale/reconciling indicators.

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0601-activity-stream.md
```

## Dependencies

- 0504.

## Scope

Persist and broadcast normalized public activity events with the full correlation chain, redaction, sequence numbers, reconnect catch-up, and stale/reconciling indicators.

## Deliverables

- Event pipeline and LiveView stream component.

## Checklist

- [x] Persist before broadcast.
- [x] Reconnect fetches after last acknowledged sequence.
- [x] Sleep gaps rendered on timelines.

## Acceptance criteria

- [x] No event lost or duplicated across reconnects.

## Verification and evidence

Passed focused commit/rollback, ordering, deduplication, reconnect catch-up, correlation/redaction, and LiveView sleep-gap tests plus the full repository quality gate. Exact commands and results are recorded in `worklog/2026-09-17-0601-activity-stream.md`.
