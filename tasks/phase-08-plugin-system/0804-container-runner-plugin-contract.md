# 0804 — Container Runner Plugin Contract and Stub

## Objective

Specify and stub the container `RunnerBridge` plugin family (Docker, OrbStack, Colima, Apple Containers): isolation claims in manifests, worktree mount and gitdir strategy, image policy, resource limits, and UI label promotion.

```yaml
status: complete
owner: codex
started_at: 2026-09-18
completed_at: 2026-09-18
worklog: worklog/2026-09-18-0804-container-runner.md
```

## Dependencies

- 0802.
- 0302.

## Scope

Specify and stub the container `RunnerBridge` plugin family (Docker, OrbStack, Colima, Apple Containers): isolation claims in manifests, worktree mount and gitdir strategy, image policy, resource limits, and UI label promotion. Implementation is deferred; the contract must be stable.

## Deliverables

- Contract document and stub plugin passing the runner conformance suite.
- Open questions list for the first real implementation.

## Checklist

- [x] Isolation claims drive UI labels.
- [x] Git strategy decided (host-side Git).

## Acceptance criteria

- [x] Stub passes runner conformance.
- [x] Domain layer unchanged by the stub.

## Verification and evidence

Runner conformance passed against the unavailable stub. The focused plugin and
settings suite passed 10 tests, the existing local-runner safety suite passed
1 property and 26 tests, and `rtk mix quality` passed 10 properties and 176
tests with no failures.
