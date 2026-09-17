# 0702 — Per-Run Extraction with Memory Operations

## Objective

Implement extraction jobs triggered per policy using the board's runtime with bounded, redacted inputs and a fixed template; classify candidates as add/update/supersede/noop against existing items; write to the candidate queue with evidence IDs..

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

- [ ] Only public artifacts and events as inputs.
- [ ] Redaction before and after synthesis.
- [ ] Evidence IDs on every candidate.

## Acceptance criteria

- [ ] Duplicate facts produce `noop`/`update`, not new items.
- [ ] Secret canaries never reach candidates.

## Verification and evidence

Run extraction fixtures with the fake adapter and canary tests.
