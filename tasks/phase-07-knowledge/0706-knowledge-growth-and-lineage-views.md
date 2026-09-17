# 0706 — Knowledge Growth and Lineage/Usage Dashboard Views

## Objective

Build the Knowledge Growth view (items over time by kind/status, consolidation history, coverage, review queue) and the Lineage/Usage view (evidence → candidate → item → runs → outcome graph with counts, usage table, unused/contradicted lists, skills view), each with table alternatives..

## Dependencies

- 0705.
- 0604.

## Scope

Build the Knowledge Growth view (items over time by kind/status, consolidation history, coverage, review queue) and the Lineage/Usage view (evidence → candidate → item → runs → outcome graph with counts, usage table, unused/contradicted lists, skills view), each with table alternatives.

## Deliverables

- LiveViews and server-side aggregations.
- Accessibility alternatives.

## Checklist

- [ ] Graph nodes open their records.
- [ ] Aggregations server-side; batched updates.

## Acceptance criteria

- [ ] Both views render for the e2e knowledge scenario.
- [ ] Useful at 5,000 items.

## Verification and evidence

Run LiveView, accessibility, and load tests.
