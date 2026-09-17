# 0305 — Pause, Hibernate, Resume, and Safe Cleanup

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0305-lifecycle-cleanup.md
```

## Objective

Implement pause, hibernate, resume, and destroy on the host runner per `docs/FLOW.md` and `docs/EXECUTION_ENVIRONMENTS.md`, including ownership verification before cleanup.

## Dependencies

- 0304.

## Scope

Implement pause, hibernate, resume, and destroy on the host runner per `docs/FLOW.md` and `docs/EXECUTION_ENVIRONMENTS.md`, including ownership verification before cleanup.

## Deliverables

- Lifecycle commands and events.
- Cleanup with ownership checks and retained-artifact listing.

## Checklist

- [x] Hibernate completes checkpoints before stopping processes.
- [x] Resume revalidates hashes and reallocates ports.
- [x] Destroy only with recorded ownership.

## Acceptance criteria

- [x] Hibernate → quit → relaunch → resume yields single stage execution.
- [x] Cleanup never removes another run's files.

## Verification and evidence

Run the hibernate/resume e2e scenario and cleanup ownership tests.
