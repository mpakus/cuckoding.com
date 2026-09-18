# Worklog — 0503 multiple boards, scheduler, and unattended mode

## Metadata

- Date/time (UTC): 2026-09-17
- Task: 0503
- Status: done
- Human/agent owner: codex
- Branch: `feature/0503-board-scheduler`
- Start revision: `2b8ac7e`
- End revision: task-closing commit on this branch; see Git history

## Acceptance criteria

- Enforce board, project, and global concurrency limits without crossing board ownership.
- Schedule ready, dependency-satisfied work fairly across boards using priority, age, and resource fit.
- Check port availability and memory headroom before dispatch.
- Pause or hibernate boards through durable state transitions.
- Keep unattended work moving only inside its declared window, queue approvals, and hold the power assertion only while eligible work remains.
- Prove two-board concurrency and an overnight unattended simulation.

## Reference coding

- The local XERJ node was unreachable for the project and all three peer prefixes, so no indexed result is claimed. Pinned source and licenses were inspected directly as required by `docs/REFERENCE_CODING.md`.
- Hydra revision `d8ad56112c2c3acfb2f65f53b6890f30a25c693c` (MIT), `electron/agents/AgentManager.ts:168-176` and `electron/agents/AgentManager.test.ts:298-317`, enforces a hard concurrent-agent cap before process creation. Cuckoding applies a global active-session admission cap before invoking its dispatcher.
- Agetor revision `eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a` (MIT), `src/bun/claude-tmux-queue.test.ts:660-688`, verifies independent per-task queues do not block each other. Cuckoding applies durable cross-board rotation rather than sharing one board's queue lock. No peer code was copied.

## Work performed

- Claimed task 0503 and restated its acceptance criteria.
- Added a stateless scheduler that reads durable ready tasks, unmet dependencies, active runs/sessions, trusted project policies, and run history before returning an admission plan.
- Added priority-and-age ordering within each board and durable last-scheduled board rotation across boards, followed by board, project, global session, port, and memory checks.
- Added replaceable resource-probe, dispatcher, notifier, and run-controller behaviours. The default host probe uses macOS `vm_stat`, physical loopback bind checks, and active port leases; final port ownership remains with `PortAllocator`.
- Added board pause/hibernate control that closes admission first and then delegates active runs to a controller holding the required live ownership handles. Reopening a board does not implicitly resume a run.
- Enforced trusted unattended policy allow/cap settings, returned stable notification keys for queued approvals, and retained the existing rule that power assertions exist only while eligible work or an unexpired unattended queue remains.
- Applied Ponytail full mode: reused task dependencies, configuration versions, run history, power events, transitions, and port leases; no migration, scheduler cursor table, or new dependency was added.
- Updated policy examples and architecture, flow, execution, power, development, plan, and task documentation.

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| `rtk xerj search ...` for project, Vibe Kanban, Agetor, and Hydra | unavailable | Local loopback node at port 9200 was unreachable; pinned source and licenses were inspected directly. |
| Pinned revision/license inspection | pass | Hydra `d8ad561...` and Agetor `eb74ab5...` are MIT; Vibe Kanban `7356549...` remains Apache-2.0. |
| `rtk mix compile --warnings-as-errors` | pass | Scheduler and policy changes compiled without warnings after the focused fix. |
| `rtk mix test test/cuckoding/execution/scheduler_test.exs test/cuckoding/power/manager_test.exs` | pass | 10 tests, 0 failures. |
| `rtk mix credo --strict` | pass | 96 source files, 1,293 modules/functions, no issues after extracting the memory-page reducer. |
| `rtk mix quality` | pass | Final run: 10 properties, 109 tests, 0 failures in 10.9 seconds; 96 files and 1,293 modules/functions had no Credo findings; warnings-as-errors compilation, Sobelow, and dependency retirement/security audit passed. |
| `rtk git diff --check` | pass | No whitespace errors. |
| Scoped changed-line secret scan and execution-boundary review | pass | No private-key, API-key, access-token, or password assignment pattern appears in the diff. The only new process call is the fixed absolute `/usr/bin/vm_stat` read-only probe; no shell, credentials, destructive command, or provider process is introduced. |

## Handoff

Task 0503 is complete after the final full gate. Continue with task 0504.
