# R040b — Tabula boards and manual drafts

Status: implemented and verified; local integration recorded in the
[worklog](../worklog/2026-10-07-R040b-tabula-drafts.md).
Owner: Codex. Branch: `feature/R040b-tabula-drafts`.

## Acceptance

- Create multiple named Tabulae inside a registered Arena with the five default
  columns and its frozen team revision. Configuration grants no execution.
- Draft and edit bounded task titles, descriptions and acceptance criteria; retain
  immutable revisions, stable identities, idempotent commands and atomic events.
- Move drafts between Specs and ToDo through accessible form controls. ToDo needs
  a description and acceptance criteria; delivery stages remain unavailable.
- Reject stale edits, foreign Arena/board/task IDs and command-key reuse. Preserve
  entered text and visible errors through live updates and recovered forms.
- Inspect saved tasks/history after reload; verify domain, LiveView, desktop/narrow
  browser rendering and packaged fresh/prior-schema startup without project writes.
- Update README, AGENTS and affected docs; verify and integrate into local main.

Git validation/init/baseline commits, custom columns, role overrides, dependencies,
file-backed accepted specs, agent planning and battles remain later slices.
