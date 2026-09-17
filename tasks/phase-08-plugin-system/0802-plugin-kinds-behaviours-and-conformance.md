# 0802 — Plugin Kinds, Behaviours, Fakes, and Conformance Suites

## Objective

Define behaviours for `knowledge_backend`, `shell_filter`, `instruction_skill`, `mcp_server`, `runner`, `metric_source`, `vcs_host`, `secret_store`, `notifier`; ship a fake and a conformance suite for each; integrate with adapters, runner, knowledge, and telemetry..

## Dependencies

- 0801.

## Scope

Define behaviours for `knowledge_backend`, `shell_filter`, `instruction_skill`, `mcp_server`, `runner`, `metric_source`, `vcs_host`, `secret_store`, `notifier`; ship a fake and a conformance suite for each; integrate with adapters, runner, knowledge, and telemetry.

## Deliverables

- Behaviours, fakes, suites.
- Integration points documented.

## Checklist

- [ ] Plugin output untrusted; numbers labeled.
- [ ] Capability token scoped to the run.

## Acceptance criteria

- [ ] Core tests pass with fakes for every kind.

## Verification and evidence

Run all conformance suites against fakes.
