# 1001 — Capability, Secret, and Plugin Hardening with Adversarial Tests

## Objective

Complete threat-model controls: capability narrowing, effective-grant audit, secret canaries everywhere, plugin undeclared-access refusal, prompt-injection fixtures in the malicious repository, token replay, cross-project knowledge access..

## Dependencies

- 0803.
- 0705.

## Scope

Complete threat-model controls: capability narrowing, effective-grant audit, secret canaries everywhere, plugin undeclared-access refusal, prompt-injection fixtures in the malicious repository, token replay, cross-project knowledge access.

## Deliverables

- Security test suite and residual-risk document.

## Checklist

- [ ] Every threat in `docs/SECURITY.md` has a test.
- [ ] Host-runner limitations documented in the UI and docs.

## Acceptance criteria

- [ ] E2E scenarios 10 and 11 pass.

## Verification and evidence

Run the security suite and record residual risks.
