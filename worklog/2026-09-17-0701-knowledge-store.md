# Worklog — 0701 knowledge store and index

## Metadata

- Date/time (UTC): 2026-09-17
- Task: 0701
- Status: complete
- Human/agent owner: codex
- Branch: `feature/0701-knowledge-store`
- Start revision: `9d40ac7`
- End revision: pending commit

## Acceptance criteria

- Keep Markdown files as content truth while SQLite mirrors validated front matter and content hashes.
- Detect missing, invalid, and hand-edited files without silently replacing indexed metadata.
- Round-trip valid fixtures byte-for-byte and require an explicit user-revision acceptance step.
- Enforce project/global scope at both sync and retrieval boundaries; refuse cross-project reads.
- Reject oversized files, symlinks, path escapes, invalid front matter, and inconsistent scope metadata.

## Reference coding

- Focused project, Hydra, and Vibe Kanban XERJ searches were attempted first; the configured node at `127.0.0.1:9200` was unreachable, so retrieval is degraded.
- Inspected pinned Agetor revision `eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a` under MIT. `src/bun/commands.ts:49-119,300-356` reads front matter only from a readable project-tree file and keeps project/global source identity explicit.
- Adapted only file authority and source separation. Cuckoding adds strict bounded metadata, exact-byte hashes, non-symlink confinement, durable mismatch state, explicit higher-version acceptance, global review, and project authorization before path resolution. Hydra and Vibe Kanban contained no more applicable store pattern; no peer code was copied.

## Work performed

- Claimed task 0701 and restated its acceptance criteria.
- Added the `knowledge_items` mirror with project/global ownership constraints, partial path uniqueness, validated kinds/statuses/confidence/validity, accepted and observed hashes, sync state, revision source, provenance, review, and supersession fields.
- Added a bounded Markdown parser that preserves exact bytes and validates required/unknown/duplicate front-matter fields, UUIDs, scope/status, version, numeric confidence, validity, provenance, triggers, and mandatory global review.
- Added confined project and global layouts, declared kind directories, non-recursive bounded scanning, symlink rejection, stable-file checks around reads, and hash verification on every retrieval.
- Added resumable sync semantics for inserted, unchanged, modified, invalid, and missing files. A changed file updates only observation state until an explicit matching-ID/scope/kind higher-version acceptance marks a user revision.
- Added project-first authorization and explicit global opt-in before resolving or reading a knowledge path; project A cannot observe project B content through this API.
- Added valid, invalid, hand-edited, and reviewed-global fixtures with focused parser, sync, exact-byte, missing, symlink, version, and scope tests.
- Updated database, architecture, knowledge, reference-coding, and implementation-plan documentation.

## Verification

- `rtk env MIX_ENV=test mix ecto.reset` — passed after moving SQLite constraints into the table definition; all migrations applied cleanly from an empty disposable test database.
- `rtk mix test test/cuckoding/knowledge/store_test.exs` — passed: 6 tests, 0 failures. Covers byte preservation, strict parsing, duplicate-key rejection, index mirroring, unchanged sync, edit mismatch, explicit higher-version acceptance, same-version refusal, missing files, invalid files, symlink insertion/replacement, cross-project refusal, and reviewed global opt-in.
- `rtk mix credo --strict` — passed over 119 source files with no issues during the focused pass.
- Final `rtk mix quality` after the stable-file hardening — passed: formatter check; compiler with warnings as errors; 10 properties and 139 tests with 0 failures; Credo over 119 source files and 1,693 modules/functions with no issues; Sobelow clean; Hex audit found no retired or advisory packages.
- `rtk git diff --check` — passed before commit.

## Handoff

Complete. Files remain the content authority, mismatch acceptance is explicit, and all retrieval is scope checked before path access.
