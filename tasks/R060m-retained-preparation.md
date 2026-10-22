# R060m — Retained worktree preparation checkpoint

Status: implemented and locally verified, 2026-10-21; local main integration below.

- [x] Add one fixed native read for an interrupted battle writer preparation.
  Require the exact original two-field battle/key request, complete retained
  preparation receipt and battle tag, source/battle/ref/head identity and the
  existing detached/locked/raw-byte worktree inspector. Never recreate a missing
  receipt, create a checkout, rewrite artifacts or infer cleanup from absence.
- [x] Freeze `worktree_recovery: retained-preparation-v1` in new Starts. Reuse
  supervised exclusive recovery dispatch only for one interrupted prepare stage
  whose other attempts are settled. Retain the Interrupted attempt unchanged;
  append public observation, advance a verified in-budget checkpoint to Paused
  and require explicit Resume with original bindings/deadline/budgets.
- [x] Timing/expiry/Stop/unknown effects cannot gain continuation; verified retained
  closure may permit confirmed Stop only. Older snapshots, missing/foreign/partial
  proofs, other native stages and multiple unfinished native claims remain blocked.
- [x] Expose dated retained preparation/closure status in the existing Inspect
  component. Keep session guards, one Start and no new setup screen.
- [x] Prove missing/tampered/foreign/cancelled native evidence, exact scoped domain
  observations, old policies, late/timing refusal, Resume integrity, no replay,
  source/checkout retention and stale/foreign UI results. Update docs/AGENTS/README,
  run native/host/package checks. Browser control timed out; LiveView rendering/
  reconnect coverage passed, full visual walkthrough remains in R080/R100.
- [ ] Merge the verified slice locally to main and delete its completed branch.

This is a specific verified checkpoint, not full crash/sleep or lost-provider-work
recovery. Multi-interruption/native admission/capture/check recovery and actual
physical/provider acceptance remain required beta work.

Evidence: [worklog](../worklog/2026-10-21-R060m-retained-preparation.md).
