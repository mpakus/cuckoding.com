# R070e — Explicit additional role workers

Status: verified implementation, 2026-10-21; local integration follows verification.

- [x] Save an optional second exact agent/model binding for each required role in
  the existing Team editor and immutable team command/revision. Keep custom
  planning roles and historical payload replay unchanged. No login/profile clone.
- [x] Primary and additional worker selectors share the existing catalog and
  validation rules; changing one agent clears only its model. Preserve dirty text,
  scope/session/key/revision gates, audited adoption and exact Disconnect unassignment.
- [x] New Starts freeze the assigned-pairs policy and all extra bindings. Allocate
  wave lane 0/1 deterministically; never substitute a busy/disconnected binding.
  Without an additional binding, that lane uses the explicitly shared primary.
  Final review/configured checks retain the primary binding. Keep two global
  workers, one turn per exact connection and independent sessions/worktrees.
- [x] Admission/Resume/Disconnect and public observation/Inspect cover every frozen
  binding, while all previous snapshots retain their original four-role policy.
- [x] Prove two simultaneous Implementor claims using separate saved connections,
  wrong/stale/foreign binding refusal, legacy behavior, Retry/Skip/recovery,
  scoped Save/adoption/Disconnect and LiveView behavior. Update docs/AGENTS/README,
  run quality/browser/build/smoke and merge locally to main.

Real-provider parallel acceptance, general toolchains, custom stages/providers,
physical recovery and signed release gates remain separate full beta work.

Evidence: 494 tests and full quality, a slot-substitution mutation, desktop/320px
source browser checks, strict/deep ad-hoc signature and packaged smoke passed.
See the worklog for exact scope and retained evidence. No real account was used.
