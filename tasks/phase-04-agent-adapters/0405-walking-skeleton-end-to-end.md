# 0405 — Walking Skeleton: One Task End to End

```yaml
status: done
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
- [x] Use the fake adapter in CI; real adapter in the demo.
- [x] Release handoff pushes to a local bare remote.

## Acceptance criteria

- [x] A real task completes end to end with evidence bundle and branch.
- [x] Sleep-gap simulation does not duplicate work.
- [x] The team records a go/no-go on the product loop.

## Verification and evidence

Attach the demo, evidence bundle, and go/no-go note to the worklog.

The deterministic CI lane and the isolated Codex demo both complete the durable loop. Real run `01a0b1e6-ae77-73d3-85cd-a368d5eed432` produced candidate `5c040f3bae8652f4cf57b9315b49debd164d4ca3`, owner-only evidence and release artifacts, a project-only knowledge candidate, visible two-step LiveView approval, and an exact non-force push to the local bare remote. The pushed SHA matches the candidate SHA. See the linked worklog and `docs/WALKING_SKELETON.md` for timings, surfaced failures, and the remaining agent-toolchain PATH follow-up.
