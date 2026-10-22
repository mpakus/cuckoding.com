# R050g — Ordered custom read-only role stages

Status: implemented, verified and merged to local main, 2026-10-22.

- [x] Let a board explicitly add, remove and reorder up to four read-only stages
  between Speculator and Implementor, using roles from its exact saved team.
  Keep the five core columns/roles/order and independent task/final review.
- [x] Append immutable workflow revisions with exact scope/revision/stable-key
  gates. Active planning/battles refuse edits; unused planning roles stay unused.
  Start freezes only the selected extra bindings and their ordered read grant.
- [x] Execute those stages in supervised task lanes with exact connection/model,
  budgets, capacity, receipt validation and no native tools or file writes.
  Preserve retry/pause/stop/recovery and historical fixed-stage snapshots.
- [x] Expose the optional configuration in Advanced and automatic card progress
  on the board. Preserve dirty forms and simple Add folder → Create tasks → Start.
- [x] Run focused transitions/executor/UI regressions, quality and package checks;
  update docs/AGENTS/README.
- [x] Merge locally to main and delete the completed feature branch (`3fa9bf8`).

Evidence: [worklog](../worklog/2026-10-22-R050g-read-role-stages.md).

Custom writing stages and arbitrary placement around final review remain separate
required work. This slice offers only real executed read stages, never inert columns.
