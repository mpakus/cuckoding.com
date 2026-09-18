# 0802 — Plugin Kinds, Behaviours, Fakes, and Conformance Suites

## Objective

Define behaviours for `knowledge_backend`, `shell_filter`, `instruction_skill`, `mcp_server`, `runner`, `metric_source`, `vcs_host`, `secret_store`, `notifier`; ship a fake and a conformance suite for each; integrate with adapters, runner, knowledge, and telemetry.

```yaml
status: done
owner: codex
started_at: 2026-09-18
worklog: worklog/2026-09-18-0802-plugin-contracts.md
```

## Dependencies

- 0801.

## Scope

Define behaviours for `knowledge_backend`, `shell_filter`, `instruction_skill`, `mcp_server`, `runner`, `metric_source`, `vcs_host`, `secret_store`, `notifier`; ship a fake and a conformance suite for each; integrate with adapters, runner, knowledge, and telemetry.

## Deliverables

- Behaviours, fakes, suites.
- Integration points documented.

## Checklist

- [x] Plugin output untrusted; numbers labeled.
- [x] Capability token scoped to the run.

## Acceptance criteria

- [x] Core tests pass with fakes for every kind.

## Verification and evidence

`rtk mix test test/cuckoding/plugins/contracts_test.exs` — 6 tests, 0 failures.
