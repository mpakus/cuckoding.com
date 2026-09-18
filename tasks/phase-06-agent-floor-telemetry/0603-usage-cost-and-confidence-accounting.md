# 0603 — Usage, Cost, and Confidence Accounting

## Objective

Implement usage records with source/confidence, versioned price catalogs, estimated cost with formula recording, and plugin optimization records as separate dimensions.

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0603-usage-cost.md
```

## Dependencies

- 0402 or 0403.

## Scope

Implement usage records with source/confidence, versioned price catalogs, estimated cost with formula recording, and plugin optimization records as separate dimensions.

## Deliverables

- Cost calculator, catalog versions, UI labels.

## Checklist

- [x] Provider-reported preferred; `≈` for estimates.
- [x] Never infer subscription marginal cost.

## Acceptance criteria

- [x] Cost reconciles with fixtures within documented limits.

## Verification and evidence

`rtk mix test test/cuckoding/telemetry/accounting_test.exs test/cuckoding/adapters/claude_code_test.exs test/cuckoding/adapters/codex_test.exs test/cuckoding_web/live/status_live_test.exs` passes 17 tests. Final `rtk mix quality` passes 10 properties and 130 tests with no failures, strict Credo, Sobelow, and dependency audit.
