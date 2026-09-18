# 0404 — Cursor Agent and OpenCode Adapters or Stable Stubs

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0404-cursor-opencode-stubs.md
```

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

- [x] Probe and capability discovery real, not assumed.
- [x] Stubs never appear as fully supported in the UI.

## Acceptance criteria

- [x] Any implemented adapter passes conformance.
- [x] Stubs cannot be selected for a stage without a visible warning.

## Verification and evidence

Conformance for implemented adapters; UI test for stub warnings.

Evidence: both integrations remain stable stubs based on current probes and accepted isolation evidence; no unsupported provider adapter was implemented. The focused stub/LiveView suite passes 5 tests, and the full repository gate passes 8 properties plus 87 tests. Both runtime controls are disabled and carry visible warnings. See the linked worklog for exact commands and limitations.
