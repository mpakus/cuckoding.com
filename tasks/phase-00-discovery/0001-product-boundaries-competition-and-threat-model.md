# 0001 — Confirm Product Boundaries, Competitive Position, and Trusted-Host Threat Model

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

- [ ] Confirm which two adapters must work at launch.
- [ ] Confirm data classes, retention defaults, and telemetry default.
- [ ] Cover repository prompt injection on the host runner, secret theft, local web access, plugin abuse, cost denial, knowledge poisoning, and sleep/wake corruption.
- [ ] Identify every mandatory human approval.
- [ ] Record residual risks the MVP discloses rather than solves.
- [ ] Schedule 3–5 user interviews with developers running two or more agents.

## Acceptance criteria

- [ ] Stakeholders can state what the MVP does and does not do without contradiction.
- [ ] Every trust boundary has at least one threat and control.
- [ ] No high-severity risk lacks an owner and verification path.
- [ ] Name, license, and pricing hypothesis are decided or explicitly deferred with a date.

## Verification and evidence

Run a tabletop for a malicious repository that instructs the agent to read `~/.ssh`, edit `.cuckoding/`, and publish knowledge; record what the host runner can and cannot stop.
