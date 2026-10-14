# R060a — Pause and resume at a completed stage

Status: completed, 2026-10-14. Branch: `feature/R060a-battle-pause-resume`.

Deliver usable Arena controls without cancelling/replaying provider work or
changing the frozen Start authority. Full crash/sleep recovery remains R060.

- [x] Pause durably closes new stage admission; an active stage may finish within
  its existing limits. Show Paused only after its retained result verifies cleanup.
- [x] Resume only a clean paused boundary, preserving scope, stages, review rounds,
  consumed turns and the original deadline. Reject stale/recovered controls.
- [x] Preserve paused exclusion, frozen drafts, Stop, independent review and
  fail-closed recovery; never resume an uncertain interrupted attempt.
- [x] Add accessible Pause/Resume and pending/deadline explanations on the same Arena.
- [x] Verify transition/race, deadline, reconnect/session and prior-schema migration
  behavior without live provider usage. Update docs/AGENTS/README.
- [x] Build and smoke-test the bundle, preserve the saved test workspace, merge
  into local main and leave the current app running.

Evidence: [worklog](../worklog/2026-10-14-R060a-battle-pause-resume.md).
