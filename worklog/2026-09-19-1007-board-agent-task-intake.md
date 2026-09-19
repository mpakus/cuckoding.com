# Worklog — 1007 board agent task intake

## Acceptance criteria

Implement the reviewable, read-only board intake flow defined in `tasks/phase-10-hardening-beta/1007-board-agent-task-intake.md`.

## Baseline

- Branch started from `ad11dce`.
- Existing unrelated public-site edits and task 1005 files were left untouched.
- `rtk xerj search --prefix cuckoding-project-v7 -k 5 "board prompt agent analyze repository docs task proposals human review import"` could not reach the configured loopback XERJ node.

## Reference coding

- XERJ was unavailable, so the pinned checkouts were inspected directly.
- Vibe Kanban, Apache-2.0, revision `735654971bd396aa97b65166955678e4c34f8bf8`: `crates/db/src/models/coding_agent_turn.rs:84-127` persists the prompt before provider session identifiers and output arrive. Adapted idea: a planning request owns durable state before launch. Cuckoding strengthens it by using the existing task/run/stage/session chain and event-before-broadcast rule.
- Hydra, MIT, revision `d8ad56112c2c3acfb2f65f53b6890f30a25c693c`: `electron/headless/HeadlessOrchestrator.ts:80-132` persists a headless run before spawn and finalizes it from child exit. Adapted idea: background planning remains a visible operation. Cuckoding routes launch through `LocalProcessRunner`, records process identity and effective grants, and never treats provider completion as permission to create tasks.

## Implementation

- Added hidden `board_intake` tasks and durable `task_proposals` with import linkage.
- Added a board prompt and assigned-role selector that prepares a normal queued run and navigates to run-scoped authentication.
- Added `AgentRuntime` so default workflows and intake runs share snapshotted role resolution and isolated runtime setup.
- Added one-stage `BoardTaskIntake` execution with a read-only/network-denied grant, closed 20-task schema, bounded output parsing, source-path validation that rejects traversal and symlinks, and a waiting review state.
- Added a proposal review form on the run page. Only selected rows become Draft delivery tasks; retrying an import returns the linked tasks without duplicating cards or import events.
- Kept planning operations on the global operation monitor while excluding their hidden owner tasks from Kanban delivery columns.
- Updated README and the product, architecture, database, flow, security, and execution-environment contracts.

## Verification

- `rtk mix test test/cuckoding/adapters/output_parser_test.exs test/cuckoding/board_task_intake_test.exs test/cuckoding_web/board_live_test.exs` — 9 tests, 0 failures.
- `rtk mix format --check-formatted` — passed.
- `rtk mix compile --warnings-as-errors` — passed.
- `rtk mix test test/cuckoding/board_task_intake_test.exs test/cuckoding/project_workflow_test.exs` — 7 tests, 0 failures after verifying that an unsupported, unselected role does not block planning.
- `rtk mix test` — 10 properties, 236 tests, 0 failures. The two emitted `fixture crash` logs are expected assertions from the plugin-supervisor restart test.
- `rtk mix credo --strict` — passed with no issues.
- `rtk mix sobelow --config` — scan complete with no findings.
- `rtk git diff --check` — passed.
- `rtk mix precommit` — unavailable because this repository defines no `precommit` Mix task; the formatter, compiler, full test, Credo, and Sobelow gates above were run explicitly.
