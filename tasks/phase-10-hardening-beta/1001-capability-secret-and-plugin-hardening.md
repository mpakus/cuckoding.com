# 1001 — Capability, Secret, and Plugin Hardening with Adversarial Tests

## Objective

Complete threat-model controls: capability narrowing, effective-grant audit, secret canaries everywhere, plugin undeclared-access refusal, prompt-injection fixtures in the malicious repository, token replay, cross-project knowledge access.

```yaml
status: complete
owner: codex
started_at: 2026-09-18
worklog: worklog/2026-09-18-1001-security-hardening.md
```

## Dependencies

- 0803.
- 0705.

## Scope

Complete threat-model controls: capability narrowing, effective-grant audit, secret canaries everywhere, plugin undeclared-access refusal, prompt-injection fixtures in the malicious repository, token replay, cross-project knowledge access.

## Deliverables

- Security test suite and residual-risk document.

## Checklist

- [x] Every threat in `docs/SECURITY.md` has a test.
- [x] Host-runner limitations documented in the UI and docs.

## Acceptance criteria

- [x] E2E scenarios 10 and 11 pass.

## Verification and evidence

The 85-test focused threat matrix and full quality gate passed. The packaged
release additionally verified credential-free durable rejection audits and the
new migration alongside normal/safe-mode startup and update rollback. Coverage
and residual risks are recorded in `docs/SECURITY_TEST_MATRIX.md`; exact
commands are in `worklog/2026-09-18-1001-security-hardening.md`.
