---
status: in_progress
owner: codex
started_at: 2026-09-30
completed_at: null
worklog: worklog/2026-09-30-1057-autonomous-project-flow.md
---

# 1057 — Describe a project and run it autonomously

Implement the authorized [adoption plan](../../docs/PAPERCLIP_ADOPTION_PLAN.md).
This task tracks the complete connected flow through the five implementation
milestones; completing one milestone does not complete the task.

- [x] AU-01: save a revisioned default team once; new projects inherit it without repeated assignment, and existing snapshots remain unchanged (source and focused fixture evidence; provider/native acceptance remains below).
- [x] AU-02: a project brief produces independently reviewed Draft tasks and durable Ready to run; no delivery before Run, no manual import, safe replay/edit/discard (source and focused fixture evidence).
- [x] AU-03: one Run authorizes the exact prepared goal, team, capabilities and finite cumulative limits; passing reviews complete locally and retain reviewed-commit provenance.
- [x] AU-04: ordinary choices, corrections, temporary waits and recoverable failures resolve automatically within separate bounded counters and shared total limits.
- [x] AU-05: criteria remain in every stage; final integration review verifies the whole goal at the final head, repairing regressions automatically; result and exceptions are accessible and actionable.
- [x] Preserve fixed batches, historical snapshots, process ownership, policy/secret confinement, project knowledge scope and separate human release approval.
- [x] Update ADRs and implementation documentation; pass relevant formatter/compiler/static/regression/migration and rendered checks with exact evidence.
- [ ] Demonstrate the full empty-folder and existing-project flow with real-provider/native recovery evidence, or explicitly retain unverified acceptance as incomplete.

Normal acceptance: configure agents once, create a project, describe the outcome,
let agents plan, press Run once, then receive a working tested result without
required human action through correction and a transient provider failure.

Current evidence: all AU-01–AU-05 behaviors are implemented in the working tree.
The current quality gate passes **469 tests and 10 properties**, plus formatter,
compiler, static analysis and dependency audit. The development bundle and sterile
migration/authentication/cleanup/update/rollback verifier pass. Desktop/narrow
browser, keyboard/focus/input retention and authenticated result/log checks pass
on the isolated preview; the later changes affect transport and recovery.

Real Codex evidence includes an empty-project one-Run drill through a plan-review
correction, injected typed provider wait and fresh-VM restart. It reused the same
run/worktree and completed Speculator stage without questions or authority changes.
A fresh **packaged control-plane** existing-project run then completed two tasks
through a real post-Run Review correction, two passing host checks and seven final
criteria, with zero questions and one Run. It used the normal production dispatcher,
sterile host PATH/HOME and the same saved team revision 1; the existing README
heading and original base commit were retained. All owned process records ended.

Live failures exposed and fixed RubyGems startup warnings corrupting transport,
missing Codex typed-failure negotiation, and unbounded task IDs in controller
output. Invalid prepared-goal decisions now use the existing finite correction
allowance with host feedback. Failed acceptance samples remain in history and are
not counted as successful runs. Exact results, hashes and limitations are in the
worklog. No comparison with Paperclip runtime reliability or cost is claimed.

The user approved device testing on October 1. The current native shell launched
successfully after a private backup, migration rehearsal and forward migration of
the app database. All original row contents across 45 tables were preserved;
integrity and foreign-key checks pass. The authenticated native dashboard loaded,
and default-team revision 1 was saved using the existing Codex account. Retained
native diagnostics exposed a wake-metadata count/list mismatch; the fix passes a
regression through the real reconciler. The rebuilt native shell launched and
graceful shutdown preserved a waiting planning run as hibernated without orphan
processes. The native empty-project demonstration reached Done with one Run, two tasks,
nine passing criteria and two successful host checks. It survived real physical
sleep and 12 background wake gaps (202,608 ms measured), retained the same
authorization and single execution of each delivery stage, and required no task
questions or manual recovery. All 20 owned process records ended; no matching
owned process remained. The original checkout stayed clean at its original head.
The desktop is now unlocked, but native navigation returned `unauthorized` after
the browser session expired. Final native result inspection needs a fresh normal
tray-menu handoff. A newer preparation is active in the same project and is left
untouched; the prior completed execution remains intact. The provider's nine-minute
implementation stage included a long silent interval before completing; no cause
or typed recovery is inferred.

A subsequent supported native restart also preserved the completed result and a
newer Ready plan exactly, including their frozen payload hashes and run counts.
It admitted no new delivery and retained database integrity. This covers the
completed/pre-Run boundary; recovery during active delivery is still unverified.

**Still open:** final native UI observation with a fresh authenticated session, full autonomous
Tauri-shell restart recovery, and signed/clean-machine release acceptance. No commit,
main integration, remote publication or installation has been performed. The task
remains in progress for these separate acceptance gates; checked implementation
slices do not mean a release-complete product.
