# 0702 — Per-Run Extraction with Memory Operations

## Objective

Implement extraction jobs triggered per policy using the board's runtime with bounded, redacted inputs and a fixed template; classify candidates as add/update/supersede/noop against existing items; write to the candidate queue with evidence IDs.

```yaml
status: done
owner: codex
started_at: 2026-09-17
worklog: worklog/2026-09-17-0702-knowledge-extraction.md
```

## Dependencies

- 0701.
- 0402 or 0403.

## Scope

Implement extraction jobs triggered per policy using the board's runtime with bounded, redacted inputs and a fixed template; classify candidates as add/update/supersede/noop against existing items; write to the candidate queue with evidence IDs.

## Deliverables

- Extraction job and template.
- Operation classifier.
- Fixtures.

## Checklist

- [x] Only public artifacts and events as inputs.
- [x] Redaction before and after synthesis.
- [x] Evidence IDs on every candidate.

## Acceptance criteria

- [x] Duplicate facts produce `noop`/`update`, not new items.
- [x] Secret canaries never reach candidates.

## Verification and evidence

`rtk mix test test/cuckoding/knowledge/extractor_test.exs` passes the fake-adapter classification, double-redaction canary, trusted evidence, policy/state, idempotency, and atomic failure scenarios. A fresh disposable test database applies the extraction migration cleanly. Final full-gate evidence is recorded in the task worklog.
