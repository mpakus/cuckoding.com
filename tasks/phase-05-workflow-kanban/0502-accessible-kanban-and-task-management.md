# 0502 — Accessible Kanban and Task Management

## Objective

Build the board Kanban, task detail, and task editing with keyboard and menu equivalents for every transition, explicit command outcomes, optimistic reconciliation, and knowledge indicators on cards.

```yaml
status: done
owner: codex
started_at: 2026-09-17
worklog: worklog/2026-09-17-0502-accessible-kanban.md
```

## Dependencies

- 0501.

## Scope

Build the board Kanban, task detail, and task editing with keyboard and menu equivalents for every transition, explicit command outcomes, optimistic reconciliation, and knowledge indicators on cards.

## Deliverables

- Board LiveView and task detail.
- Keyboard-only critical journey test.

## Checklist

- [x] Drag allowed only for permitted transitions.
- [x] No color-only status.
- [x] Filters persist.

## Acceptance criteria

- [x] WCAG 2.2 AA checks pass on the board.
- [x] Rejected transitions explain why.

## Verification and evidence

`test/cuckoding_web/board_live_test.exs` covers semantic columns, labels, text status cues, native transition controls, durable command reconciliation, explicit rejection feedback, persistent URL filters, task editing, and audit events. A real browser pass confirmed keyboard traversal through the filters, task link, transition selector, and action button; query filters survived reload. Exact gate evidence is recorded in the linked worklog.
