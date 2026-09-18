# 0602 — Host Resource Metrics and Rollups

## Objective

Collect CPU, RSS, process count, and open ports per process group at 2–5 seconds; roll up to 1-minute and stage; treat missing samples as missing; label host-runner limits as unenforced.

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0602-resource-metrics.md
```

## Dependencies

- 0302.

## Scope

Collect CPU, RSS, process count, and open ports per process group at 2–5 seconds; roll up to 1-minute and stage; treat missing samples as missing; label host-runner limits as unenforced.

## Deliverables

- Sampler, rollup jobs, retention.

## Checklist

- [x] Active vs wall time in rollups.
- [x] No interpolation.

## Acceptance criteria

- [x] Attribution to the correct session in tests.

## Verification and evidence

`rtk mix test test/cuckoding/telemetry/resource_metrics_test.exs test/cuckoding/execution/local_process_runner_test.exs` passes 12 tests. Final `rtk mix quality` passes 10 properties and 122 tests with no failures, strict Credo, Sobelow, and dependency audit.
