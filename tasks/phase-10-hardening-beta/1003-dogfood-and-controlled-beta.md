# 1003 — Dogfood and Controlled Beta

## Objective

Use Cuckoding on several real repositories and workflow types for multi-day runs; run a controlled beta with a small group; collect usability, reliability, security, and knowledge-quality findings.

```yaml
status: in_progress
owner: codex
started_at: 2026-09-18
worklog: worklog/2026-09-18-1003-dogfood-beta.md
```

## Dependencies

- 1001.
- 1002.
- 0903.

## Scope

Use Cuckoding on several real repositories and workflow types for multi-day runs; run a controlled beta with a small group; collect usability, reliability, security, and knowledge-quality findings.

## Deliverables

- Dogfood and beta reports with prioritized findings.
- Anonymized notes and decisions from 3–5 developer interviews led by the sole stakeholder.

## Checklist

- [x] Beta enrollment instructions match the current agent-first shared-profile
  flow and distinguish isolated CLI sign-in preflight from completed runs.
- [x] Current-source unsigned developer bundle passes its complete sterile
  verifier; a fresh signed/notarized enrollment build remains required.
- [ ] Confirm rotation of the provider key previously exposed in host argv
  before launching further paid provider work.
- [ ] Long runs across sleep included.
- [ ] Knowledge review quality assessed.
- [ ] Interview developers running two or more agents and review positioning, naming, licensing, and pricing hypotheses.

## Acceptance criteria

- [ ] Critical findings closed or explicitly accepted.

## Verification and evidence

Attach reports and retest evidence.
