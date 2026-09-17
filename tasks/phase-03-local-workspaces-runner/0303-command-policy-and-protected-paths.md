# 0303 — Command Policy and Protected Paths

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

- [ ] Only declared commands are executed by Cuckoding.
- [ ] Changes to protected paths flag an approval.
- [ ] Advisory fields are never rendered as enforced.

## Acceptance criteria

- [ ] Policy fixtures behave as classified.
- [ ] Protected-path edits cannot pass QA without approval.

## Verification and evidence

Run policy and protected-path tests with the malicious repository fixture.
