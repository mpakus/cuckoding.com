# R080d — Explain and repair incomplete Start bindings

Status: implementation verified, 2026-10-16; local integration pending.

- [x] Distinguish a selected agent without a model from a missing agent in Start.
  Link assignment problems to the affected Team role, not provider sign-in.
- [x] Preserve explicitly submitted agent/model pairs on Team save; changing an
  agent in the editor still clears its previous model. Keep catalog validation.
- [x] Show incomplete required roles clearly before/after saving a draft and in
  Board team. Keep saved scope adoption explicit; never pick a model/account.
- [x] Cover the missing-model blocker, successful explicit repair/adoption/Start,
  and preserved Start/session/revision gates with runnable regressions.
- [ ] Update docs, AGENTS and README; run quality, rebuild/reopen the preserved
  workspace when idle, merge to local main and delete the task branch.

[Worklog](../worklog/2026-10-16-R080d-start-bindings.md).
