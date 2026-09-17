# 0305 — Pause, Hibernate, Resume, and Safe Cleanup

## Objective

Implement pause, hibernate, resume, and destroy on the host runner per `docs/FLOW.md` and `docs/EXECUTION_ENVIRONMENTS.md`, including ownership verification before cleanup..

## Dependencies

- 0304.

## Scope

Implement pause, hibernate, resume, and destroy on the host runner per `docs/FLOW.md` and `docs/EXECUTION_ENVIRONMENTS.md`, including ownership verification before cleanup.

## Deliverables

- Lifecycle commands and events.
- Cleanup with ownership checks and retained-artifact listing.

## Checklist

- [ ] Hibernate completes checkpoints before stopping processes.
- [ ] Resume revalidates hashes and reallocates ports.
- [ ] Destroy only with recorded ownership.

## Acceptance criteria

- [ ] Hibernate → quit → relaunch → resume yields single stage execution.
- [ ] Cleanup never removes another run's files.

## Verification and evidence

Run the hibernate/resume e2e scenario and cleanup ownership tests.
