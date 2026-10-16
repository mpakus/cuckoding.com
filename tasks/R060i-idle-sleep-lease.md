# R060i — Bounded native idle-sleep assertion

Status: implemented, verified locally and merged to local main, 2026-10-15.

- [x] New Starts freeze `idle_sleep: shell-lease-v1`. Phoenix derives bounded
  eligibility from durable battle/attempt states, deadlines and cleanup grace.
- [x] Authenticated shell heartbeat requests one fixed 15-second native
  PreventUserIdleSystemSleep assertion. Release on idle/pause/quit/error/drop;
  OS timeout turns it off if renewal stalls. No display/wake/forced-sleep grant.
- [x] Keep power failures nonfatal. Record normalized native state transitions,
  show dated/freshness-aware reports in Settings and never claim guaranteed sleep
  prevention or workflow completion from this observation.
- [x] Verify native acquisition/timeout/release plus lifecycle/failure handling,
  authenticated protocol, expiry/controls, UI reconnect and unchanged saved data.
- [x] Update docs, AGENTS and README; build/smoke and merge into local main.

Physical sleep/wake, process/lease recovery, active-time accounting, parallel
workers and real-provider/release acceptance remain separate gates.

[Verification and handoff](../worklog/2026-10-15-R060i-idle-sleep-lease.md).
