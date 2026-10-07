# R040g — Revisioned task prerequisites

Status: verified; local integration pending. Owner: Codex.

- Select up to sixteen other tasks in the same Tabula as prerequisites using
  keyboard-accessible controls; show saved prerequisites on cards and in history.
- Reuse immutable draft revision content as the durable source of dependency IDs.
  Existing revisions read as no prerequisites; do not rewrite history or add
  scheduling/execution authority. Imported proposals start without dependencies.
- Validate UUIDs, bounds and duplicates; reject missing/foreign/self references and
  cycles inside the existing immediate save transaction. Recheck against the current
  graph even when another task changed after this editor opened.
- Preserve idempotent saves, stale revision rejection, atomic events/history and
  unsaved editors across live updates. A legacy save omitting prerequisites must
  preserve them; an explicit empty selection clears them.
- Cover valid chains, cycle/foreign/stale/malformed refusals, event rollback,
  prior-data compatibility, LiveView keyboard/reconnect and packaged restart.
  Update docs, AGENTS and README; merge verified local main and delete the branch.

This is manual planning structure. Provider dependency proposals, accepted specs,
battle admission and dependency scheduling remain separate work.

Evidence: [worklog](../worklog/2026-10-07-R040g-task-prerequisites.md).
