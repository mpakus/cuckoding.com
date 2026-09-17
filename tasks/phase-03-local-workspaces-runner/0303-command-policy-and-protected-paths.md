# 0303 — Command Policy and Protected Paths

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0303-command-policy.md
```

## Objective

Implement declared-command execution from `project.yml`, protected-path detection in diffs, advisory versus enforced policy classification, and flags for changes to `.cuckoding/`..

## Dependencies

- 0302.

## Scope

Implement declared-command execution from `project.yml`, protected-path detection in diffs, advisory versus enforced policy classification, and flags for changes to `.cuckoding/`.

## Deliverables

- Policy schema with enforced/advisory classification.
- Protected-path scanner on commits and diffs.
- UI labels for advisory fields.

## Checklist

- [x] Only declared commands are executed by Cuckoding.
- [x] Changes to protected paths flag an approval.
- [x] Advisory fields are never rendered as enforced.

## Acceptance criteria

- [x] Policy fixtures behave as classified.
- [x] Protected-path edits cannot pass QA without approval.

## Verification and evidence

Run policy and protected-path tests with the malicious repository fixture.
