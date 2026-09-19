# 1007 — Board agent task intake

## Goal

Let a user ask one assigned project agent to inspect repository documentation and propose board tasks without granting write access or trusting provider output.

## Acceptance criteria

- [x] The board accepts a bounded planning prompt and one configured agent role.
- [x] Submitting creates a durable, hidden planning task and run, then opens the normal run-scoped authentication page.
- [x] The selected runtime receives a read-only, network-denied planning grant and a strict structured-output schema.
- [x] Validated proposals are persisted before the UI displays them; malformed, excessive, or unbounded output fails safely.
- [x] A human can select proposals and import them as normal Draft tasks in one idempotent transaction.
- [x] Planning tasks do not appear as delivery cards on the Kanban board.
- [x] Agent/runtime failure is visible and does not create partial delivery tasks.
- [x] Focused domain and LiveView regression tests cover prompt creation, proposal review, and import.
- [x] Product, flow, database, security, and execution-environment docs describe the feature truthfully.

## Reference coding

- XERJ project search attempted first; the loopback node was unavailable.
- Inspect the pinned Vibe Kanban and Hydra sources directly and record any adapted pattern in the worklog.

## Verification

- `rtk mix format --check-formatted`
- `rtk mix compile --warnings-as-errors`
- `rtk mix test test/cuckoding/board_task_intake_test.exs test/cuckoding_web/board_live_test.exs test/cuckoding_web/run_live_test.exs`
- `rtk mix test`
- `rtk mix precommit`
