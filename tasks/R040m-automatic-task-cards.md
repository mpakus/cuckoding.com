# R040m · Create task cards automatically

Status: complete, 2026-10-13.

- [x] New consented Create tasks requests freeze automatic card creation in their setup snapshot.
- [x] Commit the validated proposal, complete prerequisite graph, original-source receipts and events in one SQLite transaction.
- [x] Duplicate/late/cancelled results and restart cannot duplicate cards or replay inference; reanalysis preserves saved edits.
- [x] Keep legacy manual imports and their provenance readable; never retroactively import old requests.
- [x] Preserve unsaved forms, session guards, Agents and Team; display created cards without per-card actions.
- [x] Verify domain/LiveView regressions, package/restart, update docs/AGENTS/README and merge local main.

No execution permission, migration or dependency is added. Start remains R050d/e.
Evidence: [worklog](../worklog/2026-10-13-R040m-automatic-task-cards.md).
