# 0704 — Review Queue, Publication, Skill Packaging, and Revocation

## Objective

Build the review queue UI with evidence preview and redaction report, project acceptance per policy, global publication with approval, `SKILL.md` packaging with manifest, supersession, revocation, and rollback..

```yaml
status: done
owner: codex
started_at: 2026-09-17
worklog: worklog/2026-09-17-0704-review-publication.md
```

## Dependencies

- 0703.

## Scope

Build the review queue UI with evidence preview and redaction report, project acceptance per policy, global publication with approval, `SKILL.md` packaging with manifest, supersession, revocation, and rollback.

## Deliverables

- Review LiveView.
- Publisher and skill packager.
- Audit events.

## Checklist

- [x] Global publication impossible without a recorded human approval.
- [x] Content hash recorded; rollback available.

## Acceptance criteria

- [x] E2E scenario 8 passes.

Task 0705 completed the final next-run usage and correction-lineage assertions.

## Verification and evidence

Run publication, revocation, and audit tests.
