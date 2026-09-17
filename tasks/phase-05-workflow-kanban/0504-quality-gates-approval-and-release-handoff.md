# 0504 — Quality Gates, Human Approval, and Host-Side Release Handoff

## Objective

Implement exit gates with typed artifact validation, the human approval stage with evidence bundle view, and the system release-handoff stage that pushes and creates a draft PR through the `VcsHost` behaviour with the user's credential from `SecretStore`..

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

- [ ] No agent process receives the GitHub credential.
- [ ] Push refused on protected branches or without approval.
- [ ] PR body includes evidence and knowledge citations.

## Acceptance criteria

- [ ] Failed QA returns structured findings.
- [ ] Approval triggers push and draft PR in the e2e scenario.

## Verification and evidence

Run gate tests, approval LiveView tests, and the release handoff against a local bare remote and a GitHub fixture.
