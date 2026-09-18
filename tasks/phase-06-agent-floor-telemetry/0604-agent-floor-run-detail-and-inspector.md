# 0604 — Agent Floor, Run Detail, and Agent Inspector

## Objective

Build the Agent Floor (role lanes, live cards, handoff arrows, attention, controls), run detail (timeline with gaps, activity, preview, artifacts, findings, cost, resources, knowledge panel placeholder, plugins), and agent inspector.

```yaml
status: done
owner: codex
started_at: 2026-09-17
worklog: worklog/2026-09-17-0604-agent-floor.md
```

## Dependencies

- 0601.
- 0602.
- 0603.

## Scope

Build the Agent Floor (role lanes, live cards, handoff arrows, attention, controls), run detail (timeline with gaps, activity, preview, artifacts, findings, cost, resources, knowledge panel placeholder, plugins), and agent inspector.

## Deliverables

- LiveViews and components.
- Table alternatives for lanes and charts.

## Checklist

- [x] Lanes groupable by role, runtime, project.
- [x] Every control gated by state.
- [x] Batched chart updates.

## Acceptance criteria

- [x] Useful at 10 live sessions and 100 cards.
- [x] Keyboard-only journey passes.

## Verification and evidence

`rtk mix test test/cuckoding_web/agent_floor_live_test.exs` passes three focused tests covering a bounded 100-card projection, a 10-session native-keyboard journey across all three views, table alternatives, accessible landmarks/names, and coalesced activity refresh. Final `rtk mix quality` passes 10 properties and 133 tests plus formatter, warnings-as-errors compilation, Credo, Sobelow, and dependency audit.
