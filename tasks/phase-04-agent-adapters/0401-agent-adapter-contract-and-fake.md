# 0401 — Define and Test the Agent Adapter Contract

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0401-agent-adapter-contract.md
```

## Objective

Implement `AgentAdapter` with all callbacks including `render_config/2`, typed request/output structures, capability discovery, normalized events, effective grant recording, error taxonomy, and a fake adapter with controllable failures.

## Dependencies

- 0202.
- 0302.

## Scope

Implement `AgentAdapter` with all callbacks including `render_config/2`, typed request/output structures, capability discovery, normalized events, effective grant recording, error taxonomy, and a fake adapter with controllable failures.

## Deliverables

- Behaviour and shared types.
- Conformance suite.
- Fake adapter.

## Checklist

- [x] Separate requested and actual model.
- [x] Source/confidence for usage.
- [x] Provider output treated as untrusted.
- [x] Sleep-gap recovery callback path.
- [x] Continuation package format.

## Acceptance criteria

- [x] Workflow code runs entirely against the fake adapter.
- [x] Unknown events fail safely.
- [x] Missing usage/model stays explicitly unavailable.

## Verification and evidence

Run conformance scenarios: reordering, duplicates, timeout, cancel, resume, sleep gap, secret canary, crash recovery.

Evidence: `rtk mix test test/cuckoding/adapters/agent_adapter_test.exs` passes 4 focused tests; `rtk mix quality` passes 8 properties and 75 tests with warnings-as-errors compilation, strict Credo, Sobelow, and dependency audit clean. Exact results and the XERJ refresh limitation are recorded in the linked worklog.
