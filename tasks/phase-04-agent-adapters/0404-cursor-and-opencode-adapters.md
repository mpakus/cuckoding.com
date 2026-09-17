# 0404 — Cursor Agent and OpenCode Adapters or Stable Stubs

## Objective

Implement Cursor Agent and OpenCode adapters where their non-interactive modes support the contract; otherwise ship stubs that report capabilities honestly and fail safely..

## Dependencies

- 0401.

## Scope

Implement Cursor Agent and OpenCode adapters where their non-interactive modes support the contract; otherwise ship stubs that report capabilities honestly and fail safely.

## Deliverables

- Adapters or stubs with capability reports.
- Fixtures where implemented.

## Checklist

- [ ] Probe and capability discovery real, not assumed.
- [ ] Stubs never appear as fully supported in the UI.

## Acceptance criteria

- [ ] Any implemented adapter passes conformance.
- [ ] Stubs cannot be selected for a stage without a visible warning.

## Verification and evidence

Conformance for implemented adapters; UI test for stub warnings.
