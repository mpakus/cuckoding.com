# 0504 — Quality Gates, Human Approval, and Host-Side Release Handoff

## Objective

Implement exit gates with typed artifact validation, the human approval stage with evidence bundle view, and the system release-handoff stage that pushes and creates a draft PR through the `VcsHost` behaviour with the user's credential from `SecretStore`.

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0504-release-gates.md
```

## Dependencies

- 0503.
- 0301.
- 0204.

## Scope

Implement exit gates with typed artifact validation, the human approval stage with evidence bundle view, and the system release-handoff stage that pushes and creates a draft PR through the `VcsHost` behaviour with the user's credential from `SecretStore`.

## Deliverables

- Gate evaluator and artifact schemas.
- Approval UI with diff and evidence.
- `VcsHost` behaviour, local Git and GitHub implementations.

## Checklist

- [x] No agent process receives the GitHub credential.
- [x] Push refused on protected branches or without approval.
- [x] PR body includes evidence and knowledge citations.

## Acceptance criteria

- [x] Failed QA returns structured findings.
- [x] Approval triggers push and draft PR in the e2e scenario.

## Verification and evidence

Passed the focused gate/approval tests and full quality suite. The release tests use a real local bare remote plus injected GitHub push/API fixtures while exercising the real approval, `SecretStore`, command, event, and release-artifact path. Exact commands and results are recorded in `worklog/2026-09-17-0504-release-gates.md`.
