# 0701 — Knowledge Store, Front Matter, and Index Sync

## Objective

Implement the Markdown knowledge layout, front-matter schema, SQLite mirror (`knowledge_items`), hash verification, user-edit detection, and project/global scopes.

```yaml
status: done
owner: codex
started_at: 2026-09-17
worklog: worklog/2026-09-17-0701-knowledge-store.md
```

## Dependencies

- 0204.
- 0201.

## Scope

Implement the Markdown knowledge layout, front-matter schema, SQLite mirror (`knowledge_items`), hash verification, user-edit detection, and project/global scopes.

## Deliverables

- Store module, parser, sync job.
- Fixtures with valid, invalid, and hand-edited files.

## Checklist

- [x] File is the content; index mirrors front matter.
- [x] Mismatch flagged, never silently resolved.

## Acceptance criteria

- [x] Sync round-trips fixtures without loss.
- [x] Cross-project retrieval is refused.

## Verification and evidence

`rtk mix test test/cuckoding/knowledge/store_test.exs` passes six parser, sync, edit-detection, symlink, scope, and exact-byte tests. A fresh disposable test database applies the migration cleanly. Final `rtk mix quality` passes 10 properties and 139 tests plus formatter, warnings-as-errors compilation, Credo, Sobelow, and dependency audit.
