# Worklog — 1033 Project states and live agent chart

## Metadata

- Date/time (UTC): 2026-09-23
- Task: 1033
- Status: done
- Human/agent owner: codex
- Branch: feature/1033-project-state-agent-chart (to be fast-forwarded to main)
- Start revision: 5d2d532
- End revision: dashboard feature commit fast-forwarded to main

## Intended outcome

Expose project task-state counts and a real-time agent-activity trend on the home dashboard, then integrate the dashboard work into `main`.

## Context inspected

- Current `main` has the prior dashboard change uncommitted; no unrelated changes in this worktree.
- One unmerged `agentdesk/reliability-modernization` branch has a separate 11,105-line Agent Desk subsystem diff. Asked the user whether “everything” includes it before any merge of that branch.
- Reuse delivery tasks from `Workflows.list_tasks/1`, measured `resource_samples`, and the existing five-second LiveView durable refresh.

## Work performed

- Counted durable delivery tasks by state across every project board. Blocked and Completed are always visible, including zero counts; the older run-attention count is labeled separately.
- Added a native SVG chart of distinct current agent sessions with measured owned-process samples in the last 12 UTC minutes. Empty minutes remain gaps, and a minute-by-minute table is available without relying on the chart.
- Reused the existing five-second durable refresh and committed-event hints. Added query and LiveView regression tests, then updated the dashboard specification. No chart dependency was added.

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| `rtk mix test test/cuckoding_web/status_live_test.exs test/cuckoding_web/agent_floor_live_test.exs` | pass | 16 tests, 0 failures. |
| `rtk mix quality` | pass | 10 properties, 306 tests, 0 failures; Credo 0 issues; Sobelow clean; Hex audit no advisories. The plugin supervisor fixture intentionally logs crashes. |
| `rtk mix assets.build` | pass | Tailwind and esbuild completed. |
| `rtk git diff --check` | pass | No whitespace errors. |
| Browser at default and 375px width | pass | Project state counts matched current durable task states; chart and accessible empty state rendered; document width matched the 375px viewport. No active agents existed to inspect a non-empty chart in the live app. |

## Limits and handoff

- The chart is scoped to currently selected active sessions, not a historical count of every agent that ran during the preceding 12 minutes. Missing sample buckets are explicitly unmeasured.
- The unrelated `agentdesk/reliability-modernization` branch remains outside this dashboard integration pending the user's scope decision.
