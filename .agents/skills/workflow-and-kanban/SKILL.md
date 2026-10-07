---
name: workflow-and-kanban
description: Edit state machines, boards, scheduling, gates, roles, or UI transitions.
---

# Workflow and Kanban

- Use `docs/FLOW.md` for column/status vocabulary and versioned workflow definitions; normal setup uses the UI, not YAML.
- Summa Rudis proposes coordination; Secutor independently judges completion; the host validates and persists both. Review returns go through Speculator.
- Transitions and events are written in one transaction; column position never drives state.
- Every drag transition has a keyboard and menu equivalent; commands return explicit outcomes.
- Track active and wall budgets separately; exhaustion requires attention and cannot reset consumed limits.
- Parallel workers use separate worktrees; combined candidates need checks/review before serialized integration. Publication stays a separate human action.

Before completion: run transition property tests, scheduler fairness tests, and LiveView keyboard tests.
