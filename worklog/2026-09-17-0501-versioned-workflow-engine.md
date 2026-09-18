# Worklog — 0501 versioned workflow engine

## Metadata

- Date/time (UTC): 2026-09-17
- Task: 0501
- Status: done
- Human/agent owner: codex
- Branch: `feature/0501-versioned-workflow-engine`
- Start revision: `07a9269`
- End revision: task-closing commit on this branch; see Git history

## Acceptance criteria

- Reject missing stages, invalid transitions, unsafe cycles, and unknown role kinds.
- Preserve immutable published workflow versions.
- Evaluate the default and a custom template, including gates and budgets.
- Route findings by transition label.

## Reference coding

- The local XERJ node was unreachable, so no indexed result is claimed. The pinned checkouts were inspected directly as required by `docs/REFERENCE_CODING.md`.
- Vibe Kanban revision `735654971bd396aa97b65166955678e4c34f8bf8` (Apache-2.0), `crates/db/src/models/task.rs:7-24`, uses one closed serialized task-state vocabulary. Cuckoding keeps its richer state vocabulary separate from workflow stage keys and adds per-version transition validation.
- Agetor revision `eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a` (MIT), `src/shared/types.ts:142-205`, exposes explicit finite retry attempt metadata. Cuckoding applies finite stage-attempt budgets inside the evaluator. Neither peer contains a closer data-driven workflow evaluator, and no peer code was copied.

## Work performed

- Claimed task 0501 and restated its acceptance criteria.
- Began a normalized workflow definition validator and evaluator within the existing `Cuckoding.Workflows` boundary; no dependency or new persistence table was added.
- Added the product default template and normalized compact definitions at publication time: display names, role kinds, finite attempt/time/token/cost budgets, knowledge triggers, gates, checkpoint intervals, and sequential transitions become explicit in the immutable stored version.
- Added entry/role/target/reachability validation and rejected pass-only strongly connected components while retaining labeled revision and fix loops.
- Added gate and budget evaluation, terminal `$done` handling, and ordered finding grouping by transition label.
- Reused the existing SQLite no-update/no-delete trigger for published workflow versions and its snapshot regression; no migration or parallel versioning mechanism was needed.
- Updated existing fixture workflows from the now-invalid empty placeholder to the smallest valid single-stage definition, and made snapshot expectations compare with the published normalized version.
- Updated workflow/development documentation, the Phase 5 plan, and the task checklist.

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| `rtk xerj search ...` for project, Agetor, and Vibe Kanban | unavailable | Local node at loopback port 9200 was unreachable; pinned source and license files were inspected directly instead. |
| Pinned revision/license inspection | pass | Agetor `eb74ab5f...` is MIT; Vibe Kanban `73565497...` is Apache-2.0. |
| `rtk mix test test/cuckoding/workflows/definition_test.exs test/cuckoding/domain_test.exs test/cuckoding/state_machine_test.exs test/cuckoding/walking_skeleton_test.exs` | pass | 5 properties, 19 tests, 0 failures. |
| `rtk mix test test/cuckoding/workflows/definition_test.exs` after simplification | pass | 2 properties, 4 tests, 0 failures. |
| `rtk mix credo --strict` | pass | 91 source files, 1,190 modules/functions, no issues before the final malformed-budget guard. |
| `rtk mix quality` | pass | 10 properties, 100 tests, 0 failures in 10.6 seconds; 1,192 modules/functions with no Credo findings; warnings-as-errors compilation, Sobelow, and dependency retirement/security audit passed. |
| `rtk git diff --check` | pass | No whitespace errors after the final source and documentation edits. |

## Handoff

Task 0501 is complete after the final full gate. Continue with task 0502.
