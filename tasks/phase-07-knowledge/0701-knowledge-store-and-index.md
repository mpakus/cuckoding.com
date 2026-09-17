# 0701 — Knowledge Store, Front Matter, and Index Sync

## Objective

Implement the Markdown knowledge layout, front-matter schema, SQLite mirror (`knowledge_items`), hash verification, user-edit detection, and project/global scopes..

## Dependencies

- 0204.
- 0201.

## Scope

Implement the Markdown knowledge layout, front-matter schema, SQLite mirror (`knowledge_items`), hash verification, user-edit detection, and project/global scopes.

## Deliverables

- Store module, parser, sync job.
- Fixtures with valid, invalid, and hand-edited files.

## Checklist

- [ ] File is the content; index mirrors front matter.
- [ ] Mismatch flagged, never silently resolved.

## Acceptance criteria

- [ ] Sync round-trips fixtures without loss.
- [ ] Cross-project retrieval is refused.

## Verification and evidence

Run parser, sync, and scope tests.
