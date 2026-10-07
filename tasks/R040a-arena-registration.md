# R040a — Arena registration

Status: implemented and verified; local integration recorded in the
[worklog](../worklog/2026-10-07-R040a-arena-registration.md).
Owner: Codex. Branch: `feature/R040a-arena-registration`.

## Acceptance

- Open a native macOS folder chooser from authenticated Arenas; allow one existing
  directory, with cancellation, a two-minute deadline and durable interruption.
- Preview its canonical path and unverified Git-entry presence without reading
  project files, running Git, creating directories or launching an agent.
- Confirm registration with a name and the displayed immutable default-team
  revision. Persist idempotent intent, Arena identity and audit events in SQLite.
- Reject duplicate/replaced folders, unsafe roots, malformed input and stale
  results. Team changes cannot rewrite an Arena's inherited revision.
- Keep input and errors across live updates; inspect inherited roles after reload.
- Test fresh/prior schema, native chooser and cleanup, domain and LiveView behavior;
  update README, AGENTS and affected docs, then integrate into local main.

Git repository validation/init/initial commits, team overrides, Tabulae and task
planning remain later R040 slices. Registration grants no execution or file access.
