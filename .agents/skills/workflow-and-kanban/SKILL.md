---
name: workflow-and-kanban
description: Edit state machines, boards, scheduling, gates, roles, or UI transitions.
---

# Workflow and Kanban

- Task states are the single vocabulary in `docs/FLOW.md`; workflow YAML uses stage keys, role kinds (`agent`, `human`, `system`), and transition labels.
- Transitions and events are written in one transaction; column position never drives state.
- Every drag transition has a keyboard and menu equivalent; commands return explicit outcomes.
- Budgets track active and wall time separately; exhaustion moves to `waiting`.
- The release handoff is a system stage executed host-side after approval.

Before completion: run transition property tests, scheduler fairness tests, and LiveView keyboard tests.
