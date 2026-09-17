# 0401 — Define and Test the Agent Adapter Contract

## Objective

Implement `AgentAdapter` with all callbacks including `render_config/2`, typed request/output structures, capability discovery, normalized events, effective grant recording, error taxonomy, and a fake adapter with controllable failures..

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

- [ ] Separate requested and actual model.
- [ ] Source/confidence for usage.
- [ ] Provider output treated as untrusted.
- [ ] Sleep-gap recovery callback path.
- [ ] Continuation package format.

## Acceptance criteria

- [ ] Workflow code runs entirely against the fake adapter.
- [ ] Unknown events fail safely.
- [ ] Missing usage/model stays explicitly unavailable.

## Verification and evidence

Run conformance scenarios: reordering, duplicates, timeout, cancel, resume, sleep gap, secret canary, crash recovery.
