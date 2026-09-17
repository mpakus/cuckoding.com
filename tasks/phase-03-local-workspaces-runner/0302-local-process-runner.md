# 0302 — LocalProcessRunner with Process Groups and Environment Allowlist

## Objective

Implement `RunnerBridge` for the host: prepare, start, exec, inspect, stream events, destroy; process groups; PID and start identity; termination ladder; environment allowlist; output bounds and redaction..

## Dependencies

- 0301.

## Scope

Implement `RunnerBridge` for the host: prepare, start, exec, inspect, stream events, destroy; process groups; PID and start identity; termination ladder; environment allowlist; output bounds and redaction.

## Deliverables

- `RunnerBridge` behaviour, `LocalProcessRunner`, fake runner.
- Process supervision and termination ladder.
- Resource sampler for process groups.

## Checklist

- [ ] Every process in its own group.
- [ ] Environment built from allowlist only.
- [ ] Every ladder step recorded.

## Acceptance criteria

- [ ] Killing a run leaves no orphan.
- [ ] Output beyond limits is truncated with an artifact, never lost silently.

## Verification and evidence

Run process-group cleanup, timeout, PID-reuse, and environment scrubbing tests.
