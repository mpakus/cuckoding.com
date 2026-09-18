# 0706 — Knowledge Growth and Lineage/Usage Dashboard Views

## Objective

Build the Knowledge Growth view (items over time by kind/status, consolidation history, coverage, review queue) and the Lineage/Usage view (evidence → candidate → item → runs → outcome graph with counts, usage table, unused/contradicted lists, skills view), each with table alternatives.

```yaml
status: done
owner: codex
started_at: 2026-09-18
worklog: worklog/2026-09-18-0706-knowledge-views.md
```

## Dependencies

- 0705.
- 0604.

## Scope

Build the Knowledge Growth view (items over time by kind/status, consolidation history, coverage, review queue) and the Lineage/Usage view (evidence → candidate → item → runs → outcome graph with counts, usage table, unused/contradicted lists, skills view), each with table alternatives.

## Deliverables

- LiveViews and server-side aggregations.
- Accessibility alternatives.

## Checklist

- [x] Graph nodes open their records.
- [x] Aggregations server-side; batched updates.

## Acceptance criteria

- [x] Both views render for the e2e knowledge scenario.
- [x] Useful at 5,000 items.

## Verification and evidence

- Focused LiveView, accessibility, lineage, and 5,000-item load checks passed: 5 tests, 0 failures.
- Full `rtk mix quality` passed on retry: 10 properties, 156 tests, 0 failures; Credo, Sobelow, and dependency audit clean.
