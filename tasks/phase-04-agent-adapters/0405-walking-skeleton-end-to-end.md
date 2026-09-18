# 0405 — Walking Skeleton: One Task End to End

```yaml
status: in_progress
owner: codex
started_at: 2026-09-17
worklog: worklog/2026-09-17-0405-walking-skeleton.md
```

## Objective

Deliver the thinnest complete slice before building more infrastructure: create a project, one board with the default workflow, one task; run spec → development → QA with one adapter on the host runner; human approval in a minimal LiveView; host-side release handoff to a local bare remote; hibernate/resume across a simulated sleep gap; extract knowledge candidates as plain files (no review UI yet)..

## Dependencies

- 0402 or 0403.
- 0306.

## Scope

Deliver the thinnest complete slice before building more infrastructure: create a project, one board with the default workflow, one task; run spec → development → QA with one adapter on the host runner; human approval in a minimal LiveView; host-side release handoff to a local bare remote; hibernate/resume across a simulated sleep gap; extract knowledge candidates as plain files (no review UI yet).

## Deliverables

- Runnable skeleton with a minimal UI.
- Demo recording and timings.
- List of what was faked and what must be replaced.
- Product judgment note: is the loop valuable enough to continue?

## Checklist

- [x] One adapter, one board, host runner, no plugins.
- [ ] Use the fake adapter in CI; real adapter in the demo.
- [x] Release handoff pushes to a local bare remote.

## Acceptance criteria

- [ ] A real task completes end to end with evidence bundle and branch.
- [x] Sleep-gap simulation does not duplicate work.
- [x] The team records a go/no-go on the product loop.

## Verification and evidence

Attach the demo, evidence bundle, and go/no-go note to the worklog.

Partial evidence merged by explicit stakeholder direction: the deterministic CI lane completes the full durable loop with real SQLite, worktree, commit, sleep/resume, LiveView confirmation, evidence files, and local bare push. The full repository gate passes 8 properties and 90 tests. The prepared isolated Codex demo remains at the real-provider gate while its run-scoped device login is pending; task status therefore remains `in_progress`. See the linked worklog and `docs/WALKING_SKELETON.md`.
