# R060d — Recover settled battle checkpoints

Status: completed, 2026-10-14. Branch: `feature/R060d-restart-checkpoints`.

- [x] Audit PLAN against current implementation and distinguish delivered controls
  from unfinished recovery, concurrency, providers, UX and release acceptance.
- [x] On startup, turn running/pausing battles with no unfinished claim and fully
  settled cleanup receipts into Paused. Preserve stage, context, snapshots,
  attempts, counters and original deadline; no implicit provider or native replay.
- [x] Record recovery reason/control revision/event atomically. Retain clean
  existing pauses, reject expired/exhausted authority on Resume, and leave unknown,
  historical missing-cleanup or interrupted effects needing inspection.
- [x] Explain the recovered pause in Arena; use existing session/revision guards
  and exact binding/native integrity checks on explicit Resume.
- [x] Test restart at every stage boundary, retried/skipped histories, in-flight
  interruption, idempotence, worker dispatch and stale/reconnected UI controls.
- [x] Update docs/AGENTS/README, run quality/build/smoke, preserve the saved test
  workspace, commit and merge local main. No push or live provider inference.

Evidence: [worklog](../worklog/2026-10-14-R060d-restart-checkpoints.md).
