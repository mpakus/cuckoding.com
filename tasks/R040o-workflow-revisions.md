# R040o — Versioned Tabula workflow foundation

Status: implemented and verified, 2026-10-22; local integration recorded below.

- [x] Add an additive immutable per-board workflow revision ledger. Existing
  Tabula rows/definitions remain byte-for-byte unchanged and supply revision zero;
  no old command, task, team, battle or grant is rewritten. Verify a backed-up
  fifteen-schema upgrade and old-bundle refusal of the new schema.
- [x] Add exact scoped/revision-guarded, stable-key audited column-label saves.
  Preserve the five required semantic keys, roles and order. Validate closed
  bounded unique names; refuse foreign/stale, active planning/battle and unchanged
  writes. Freeze the selected definition/revision in new Starts.
- [x] Add Board columns in Advanced using the shared dialog and a guarded
  LiveComponent. Keep dirty text through updates, require explicit discard/reload,
  reject recovered/foreign/session-expired forms and show bounded dated history.
  The normal Add folder → Create tasks → Start flow stays unchanged.
- [x] Prove labels render on the board and still permit the existing Start/review
  loop, while earlier battle snapshots retain their original workflow. Run focused,
  full quality, migration, source/package checks; update docs/AGENTS/README and
  prepare local integration to main.

- [ ] Merge locally to main and delete the completed feature branch.

Evidence: [worklog](../worklog/2026-10-22-R040o-workflow-revisions.md).

This is the durable prerequisite for ordered custom role stages. Adding/reordering
custom steps and executing their actual grants remain required subsequent work;
they are not represented by inert configurable columns in this slice.
