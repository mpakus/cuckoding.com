# 0302 — LocalProcessRunner with Process Groups and Environment Allowlist

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0302-local-process-runner.md
```

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

- [x] Every process in its own group.
- [x] Environment built from allowlist only.
- [x] Every ladder step recorded.

## Acceptance criteria

- [x] Killing a run leaves no orphan.
- [x] Output beyond limits is truncated with an artifact, never lost silently.

## Verification and evidence

Run process-group cleanup, timeout, PID-reuse, and environment scrubbing tests.
