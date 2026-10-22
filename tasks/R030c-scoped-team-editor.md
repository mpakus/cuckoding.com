# R030c — Arena and Tabula team overrides

Status: complete, 2026-10-21. [Evidence](../worklog/2026-10-21-R030c-scoped-team-editor.md).

- [x] Reuse the Team editor for an explicitly selected Arena or Tabula. Keep the
  default editor and its existing board-repair/adoption navigation unchanged.
- [x] Save exact scope/revision/bindings and immutable team/adoption/audit records
  atomically. Scoped revisions must never become the global default. Active board
  planning blocks changes; old requests, battles and sibling scopes stay unchanged.
- [x] Retain model validation, custom-role removal confirmation, session/form
  guards, dirty text and useful stale/scope errors. Navigation never saves/adopts.
- [x] Disconnect unassigns exact current scoped bindings without creating default
  drift. No fallback, role tools or new execution stages.
- [x] Domain/LiveView/rollback/legacy and adversarial verification, relevant
  quality/build/smoke, docs/AGENTS/README and local main merge/branch deletion.
