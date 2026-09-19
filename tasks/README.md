# Implementation Tasks

Tasks are grouped by gated phase and numbered so dependencies are visible. Complete phases in order unless a task explicitly states that it can run in parallel. The task file is the unit of assignment, review, and worklog reporting. Task 0405 (walking skeleton) is a mandatory checkpoint: no Phase 5+ work starts before its go/no-go note exists.

## Working protocol

1. Read root `AGENTS.md`, the task, and linked documents/skills.
2. Confirm dependencies and create the task branch.
3. Add a worklog entry using `worklog/TEMPLATE.md`.
4. Implement only the stated scope; propose scope changes separately.
5. Run every applicable verification item.
6. Record artifacts, decisions, test output, and residual risk.
7. Check acceptance items only when evidence exists.

## Phase index

| Phase | Goal | Tasks |
| --- | --- | --- |
| 00 | Validate boundaries, competition, threat model, runtime, shell, power handling, reference coding, and implementation readiness | 0001, 0002, 0003, 0004, 0005, 0006, 0007 |
| 01 | Establish Phoenix and durable execution foundation | 0101, 0102, 0103 |
| 02 | Implement durable domain, persistence, secrets | 0201, 0202, 0203, 0204 |
| 03 | Isolate Git workspaces and host process runtimes; ports; power | 0301, 0302, 0303, 0304, 0305, 0306 |
| 04 | Add provider-neutral agent adapters and the walking skeleton | 0401, 0402, 0403, 0404, 0405 |
| 05 | Deliver workflows, multiple boards, Kanban, approvals, release handoff | 0501, 0502, 0503, 0504 |
| 06 | Deliver Agent Floor and telemetry | 0601, 0602, 0603, 0604 |
| 07 | Deliver knowledge store, pipeline, injection, usage, and views | 0701, 0702, 0703, 0704, 0705, 0706 |
| 08 | Deliver the plugin system and reference plugins | 0801, 0802, 0803, 0804 |
| 09 | Deliver the menubar shell, packaging, updater | 0901, 0902, 0903, 0904 |
| 10 | Harden security and recovery; beta; release | 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010 |

## Status header

Add this block near the top while executing a task:

```yaml
status: not_started | in_progress | blocked | review | done
owner: name-or-agent-session
started_at: YYYY-MM-DD
completed_at: null
worklog: worklog/YYYY-MM-DD-task-id.md
```

Do not rewrite acceptance criteria to match an incomplete implementation. Record any deviation in the worklog and create a follow-up task.
