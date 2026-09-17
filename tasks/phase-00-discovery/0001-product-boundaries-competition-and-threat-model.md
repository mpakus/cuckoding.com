# 0001 — Confirm Product Boundaries, Competitive Position, and Trusted-Host Threat Model

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0001-product-threat-model.md
```

## Objective

Review `docs/PRODUCT.md`, `docs/ARCHITECTURE.md`, `docs/SECURITY.md`, and `docs/EXECUTION_ENVIRONMENTS.md`.

## Dependencies

- None.

## Scope

Review `docs/PRODUCT.md`, `docs/ARCHITECTURE.md`, `docs/SECURITY.md`, and `docs/EXECUTION_ENVIRONMENTS.md`. Confirm macOS Apple Silicon, single-user, host-runner MVP, two launch adapters, approval gates, and non-goals. Survey competing agent orchestrators and native runtime features (worktrees, subagents, memory) and write the positioning. Decide product name (the current name has a poor connotation for English-speaking markets), open-core license, and pricing hypothesis. Enumerate assets, trust boundaries, attackers, abuse cases, and mitigations for the trusted-host model.

## Deliverables

- Approved MVP scope and non-goals.
- Competitive scan and positioning statement.
- Name, license, and pricing hypothesis recorded as ADRs.
- Threat-model diagram and risk register with owner, likelihood, impact, mitigation, and validation task.
- List of unresolved product/security decisions.

## Checklist

- [x] Confirm which two adapters must work at launch.
- [x] Confirm data classes, retention defaults, and telemetry default.
- [x] Cover repository prompt injection on the host runner, secret theft, local web access, plugin abuse, cost denial, knowledge poisoning, and sleep/wake corruption.
- [x] Identify every mandatory human approval.
- [x] Record residual risks the MVP discloses rather than solves.
- [x] Assign the sole stakeholder as interviewer for 3–5 developer interviews during controlled beta task 1003.

## Acceptance criteria

- [x] The sole stakeholder approved the documented MVP boundary on 2026-09-17.
- [x] Every trust boundary has at least one threat and control.
- [x] No high-severity risk lacks an owner and verification path.
- [x] Name, license, and pricing hypothesis are decided or explicitly deferred with a date.

## Verification and evidence

Run a tabletop for a malicious repository that instructs the agent to read `~/.ssh`, edit `.cuckoding/`, and publish knowledge; record what the host runner can and cannot stop.
