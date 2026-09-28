---
status: done
owner: codex
started_at: 2026-09-28
completed_at: 2026-09-28
worklog: worklog/2026-09-28-1055-autonomous-board.md
---

# 1055 — Autonomous board orchestration with the existing team

Implement the approved autonomous-goal plan as an opt-in extension of fixed board
batches. Retain saved roles, sequential delivery, ACP and reviewed commit handoff.

- [x] Persist explicit start authorization, finite limits, immutable plan revisions and historical membership; support an empty board.
- [x] Speculator proposes tasks; the separately scoped assigned Reviewer accepts or returns corrections; atomically import accepted tasks and dependencies.
- [x] Allow reviewed in-scope additions, splits and priority changes only for unstarted work; reject stale changes, cycles, foreign references and scope expansion.
- [x] Persist logical role conversations and validated native resume or bounded public-evidence continuation, with separate attempts/accounting.
- [x] Continue independent tasks after task-local blockers; defer descendants, retain evidence and require attention when only blocked work remains.
- [x] Bound transient recovery, plan revisions, delivery task creation and review attempts across retries; global authorization/policy/provenance/process failures stop admission.
- [x] Persist questions/answers and preserve pause/resume/stop/skip/retry through planning, delivery and recovery.
- [x] Add accessible modal/dashboard views for goal, plan, conversations, recovery, attention and complete accounting.
- [x] Preserve fixed-batch and manual another-model review contracts; run migration, adversarial, workflow, continuation, control and rendered regressions plus quality/motion gates.
- [x] Update README and affected product/architecture/DB/flow/security/runtime documentation; record real-provider and packaged acceptance separately.

Defaults: 20 lifetime delivery tasks, three post-initial plan revision cycles,
two transient retries per task, three Review attempts across retries. No A2A,
general MCP server, parallel delivery, remote workers, automatic publication or
permission expansion. These limits and automatic local completion require the
start-time consent; historical executions gain no authority.

Source/fixture acceptance is complete. Real-provider autonomous continuation,
packaged-app and physical sleep/wake evidence remain open in the worklog and
are not represented as passing by this task.
