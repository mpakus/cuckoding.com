# R060n — Retained parallel preparation checkpoint

Status: implemented, locally verified and merged to main, 2026-10-21 (`1dc6d21`).

- [x] Freeze `worktree_wave_recovery: retained-preparation-wave-v1` in new Starts.
  Preserve R060m single-preparation behavior and older two-claim refusal.
- [x] Only two exact restart-interrupted writer preparations with all other claims
  settled may queue the existing fixed reads, exclusively through supervised workers.
  Record ordered membership and observations; never create/replay preparations.
- [x] Advance both task checkpoints atomically to Paused only after both reads
  verify and both original stage/battle deadlines remain valid. Explicit Resume
  retains all bindings, budgets and wave slots. Keep Interrupted attempts unchanged.
- [x] Failed/partial/foreign evidence, mixed native/provider stages, Stop/timing
  fences and expired receipts cannot partially advance a wave. Verified per-attempt
  closure may satisfy Stop only when every original attempt is closed.
- [x] Test sequential reads, worker restart, exact scope, old policies, all-or-none
  checkpoint, deadline/fence failures and no replay. Reuse the dated existing
  Inspect surface. Update docs/AGENTS/README and verify.
- [x] Merge the verified slice locally to main and delete its completed branch.

This covers only two completed writer preparations whose replies were lost.
Admission/capture/check/provider-session and physical sleep recovery stay open.

Evidence: [worklog](../worklog/2026-10-21-R060n-wave-preparation.md).
