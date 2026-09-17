# 0804 — Container Runner Plugin Contract and Stub

## Objective

Specify and stub the container `RunnerBridge` plugin family (Docker, OrbStack, Colima, Apple Containers): isolation claims in manifests, worktree mount and gitdir strategy, image policy, resource limits, and UI label promotion.

## Dependencies

- 0802.
- 0302.

## Scope

Specify and stub the container `RunnerBridge` plugin family (Docker, OrbStack, Colima, Apple Containers): isolation claims in manifests, worktree mount and gitdir strategy, image policy, resource limits, and UI label promotion. Implementation is deferred; the contract must be stable.

## Deliverables

- Contract document and stub plugin passing the runner conformance suite.
- Open questions list for the first real implementation.

## Checklist

- [ ] Isolation claims drive UI labels.
- [ ] Git strategy decided (host-side Git recommended).

## Acceptance criteria

- [ ] Stub passes runner conformance.
- [ ] Domain layer unchanged by the stub.

## Verification and evidence

Run runner conformance against the stub.
