# R050k — Verify protected guest worker budgets and watchdog

Status: completed prerequisite probe, 2026-10-23. Base `5921ad9`; local integration only.

- [x] Reuse the disposable pinned guest prototype. Put workers under a distinct
  non-root identity, no-new-privileges and nondelegated kernel resource limits;
  keep the root watchdog outside that resource group.
- [x] Prove denial of watchdog signalling, policy modification and group escape;
  exercise bounded PID/memory pressure, independent guest deadline, atomic
  group kill and zero-live-process observation before guest shutdown.
- [x] Observe native guest shutdown while the VM keeper survives client loss.
  Retain abrupt keeper death as unverified without a native stop observation;
  never upgrade missing proof or guest text into workflow authority.
- [x] Keep all workloads finite, no network/host shares/provider/project, and no
  shipping grant/entitlement changes. Re-run original probe cases, strict build,
  relevant adversarial checks and update docs/AGENTS/README; merge local main.

This advances the subprocess prerequisite. Actual toolchains, candidate/grant/
receipt/OTP integration, keeper-loss reconciliation, sleep and release acceptance
remain part of the full beta objective.

Nine actual guest cases passed (five original, four protected). Fixed root-worker
mutation is rejected; native keeper death still does not establish cleanup.
[Evidence](../worklog/2026-10-23-R050k-protected-guest-watchdog.md).
