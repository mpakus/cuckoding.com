# Worklog — 0704 review, publication, and skills

## Metadata

- Date/time (UTC): 2026-09-17
- Task: 0704
- Status: done
- Human/agent owner: codex
- Branch: `feature/0704-review-publication`
- Start revision: `b9aa034`
- End revision: `b518af7`

## Acceptance criteria

- Render a keyboard-operable review queue with evidence and redaction state.
- Apply project acceptance policy in the domain layer and require recorded human approval before any global publication.
- Package approved procedures as bounded, versioned `SKILL.md` artifacts with a manifest and content hash.
- Preserve supersession/revocation history and support audited rollback.
- Pass E2E scenario 8 plus focused publication, revocation, audit, and accessibility checks.

## Reference coding

- Focused project and Agetor XERJ searches were attempted first; the configured node at `localhost:9200` was unreachable, so retrieval was degraded to direct pinned-source inspection.
- Inspected pinned Agetor revision `eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a` under MIT. `src/bun/task-plans.ts:157-179` validates that a durable record is still pending before a non-idempotent approval side effect.
- Adapted only the ordering and idempotency principle. Cuckoding additionally binds approval to the exact run and subject, requires the latest matching decision, records a run event, confines file writes, keeps append-only versions, and verifies content hashes. No peer code was copied.
- Applied Ponytail full `4.10.0` under MIT, the project knowledge/security skills, Phoenix domain/UI guidance, and native-element accessibility guidance. No dependency or second UI framework was added.

## Work performed

- Claimed task 0704 and restated its acceptance criteria.
- Added human and policy-gated candidate review. Accepted add/update/supersede operations materialize new project Markdown; corrected items point to the prior item and never overwrite history.
- Added candidate-specific approval requests and exact latest-approval validation before global publication. A wrong, pending, stale, mismatched-run, or mismatched-actor approval cannot publish.
- Added append-only publication versions with exact Markdown and hashes, audited publish/revoke/rollback events, current global-file revision, and rollback to a reviewed prior body.
- Added bounded Agent Skills-compatible `SKILL.md` packaging for approved recipes, semantic versions, manifests, hashes, provenance, safety, and verification metadata.
- Added the bounded `/knowledge` LiveView with evidence/redaction disclosure, labeled native review/approval forms, status/alert feedback, publication history, and reconnect from durable state.
- Added adversarial checks for unapproved and wrong-subject publication, append-only publication/package tables, redaction canaries, policy refusal, supersession history, migration reversal, keyboard controls, and reconnect.
- Updated architecture, database, knowledge, dashboard, and implementation-plan documentation.

## Verification

- `rtk env MIX_ENV=test mix ecto.reset` — passed from an empty disposable test database with the new candidate columns, partial uniqueness, append-only publication/package tables, and triggers.
- `rtk env MIX_ENV=test mix ecto.rollback --step 1 && rtk env MIX_ENV=test mix ecto.migrate` — passed; the forward migration reverses and reapplies cleanly.
- `rtk mix test test/cuckoding/knowledge/publication_service_test.exs test/cuckoding_web/knowledge_review_live_test.exs` — passed: 6 tests, 0 failures.
- `rtk mix test test/cuckoding/knowledge/publication_service_test.exs test/cuckoding_web/knowledge_review_live_test.exs test/cuckoding/knowledge/store_test.exs test/cuckoding/knowledge/extractor_test.exs test/cuckoding/knowledge/consolidator_test.exs` — passed before the final supersession fixture: 18 tests, 0 failures.
- `rtk mix quality` — passed: formatter, unused-dependency check, compiler with warnings as errors, 10 properties and 152 tests with 0 failures, Credo over 129 source files with no issues, Sobelow clean, and Hex audit with no retired or advisory packages.
- `rtk git diff --check` — passed before commit.

## Handoff

Complete. Task 0705 supplied the deferred next-run usage and correction-lineage evidence, so scenario 8 now passes end to end.
