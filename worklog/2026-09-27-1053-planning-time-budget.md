# 1053 — Planning time budget

Claim task 1053 only, on `fix/1053-planning-time-budget`, starting from clean
local main `c7666b7`. The user reran planning after task 1052 and reported an
exit-status-1 failure. Continue the existing fix/integration/restart workflow.

Acceptance: planning honors its selected role's saved finite time budget,
shows the limit before launch, distinguishes timeout from generic process
failure, retains public activity and historical grants/evidence, and passes
focused and full checks before local integration and a safe app restart.
No paid provider run or task import will be triggered by this work.

## Diagnosis and references

Applied Ponytail 4.10.0 (MIT), full mode, agent-adapter, security-review,
workflow-and-kanban, elixir-phoenix-liveview, and quality-gates. Required product,
architecture, database, flow, security and execution-environment documents were
read during the preceding work. Inspected intake creation/execution, immutable
run snapshots, workflow budgets, runner completion, failure projection, and the
run page. Existing `WalkingSkeleton` stage grants already derive `wall_ms` from
the saved workflow; reuse that policy boundary rather than adding another
budget configuration. No external code adapted. The local XERJ endpoint was
unavailable in the preceding task; direct repository references suffice for
this existing path.

The live database was opened read-only. The new run started its process at
2026-09-27 04:43:27.770623 UTC and recorded `process.timeout` at
04:48:27.779564, then exit status 1 with `timed_out: true`. Intake ignored this
flag and reported `adapter_exit`. Its request hard-coded 300,000 ms even though
the saved Speculator stage allows 3,600,000 ms. The log ends during repository
inspection; there is no completed final task result. Task 1052's parser fix
successfully indexed this run's activity; this failure has a different cause.

## Work and verification

Planning and proposal review now derive their process deadline from the
selected role's immutable workflow snapshot, using the lowest matching budget
if a role has multiple stages. A role without a matching stage retains the
existing five-minute fallback. The queued run shows its budget before explicit
start; review options show their corresponding limits. Existing session grants
and failed-run evidence are never rewritten, and no active budget is expanded.

`Adapters.check_process_result/1` centralizes timeout precedence for both
planning and delivery. It reads the trusted host-runner flag, not provider
text. Even a zero exit after host termination fails as `agent_timeout`.
Both flows retain provider activity before checking the outcome. Existing
schema-error handling and read-only/network-denied grants remain in place.

- `rtk env -u CR_PAT mix test test/cuckoding/board_task_intake_test.exs` first
  reproduced the missing budget display and hard-coded 300,000 ms grant:
  8 tests, 2 failures, seed 681134.
- `rtk env -u CR_PAT mix test test/cuckoding/board_task_intake_test.exs test/cuckoding/execution/local_process_runner_test.exs test/cuckoding/walking_skeleton_test.exs`:
  51 tests, 1 fixture-setup failure, seed 929272. The new fixture needed a
  legacy saved CLI snapshot; current board-role creation correctly rejected an
  unbound Codex account. Adjusted test data only, preserving account checks.
- `rtk env -u CR_PAT mix test test/cuckoding/board_task_intake_test.exs test/cuckoding/adapters/agent_adapter_test.exs`:
  15 tests passed, seed 898757. Coverage includes saved 60-minute grants,
  role-specific/minimum budgets, five-minute fallback, timeout precedence over
  exit 0/1/143, normal exits, and a real host deadline using a synthetic CLI and
  one-second test budget. That fixture proves a blocked run, no proposals,
  retained activity, a durable `agent_timeout` cause, and the rendered alert.
- `rtk env -u CR_PAT mix format lib/cuckoding/board_task_intake.ex lib/cuckoding/contexts.ex lib/cuckoding/walking_skeleton.ex lib/cuckoding/orchestration_failure.ex lib/cuckoding_web/live/run_live.ex test/cuckoding/board_task_intake_test.exs`:
  passed. The updated intake and adapter test files were formatted afterward.
- `rtk git diff --check`: passed.
- Full `rtk env -u CR_PAT mix quality`: passed 373 tests and 10 properties,
  seed 545340, formatting, unused-lock check, warnings-as-errors compilation,
  strict Credo, Sobelow, and Hex audit. Expected crash-fixture logs belong to
  supervisor recovery coverage.

The fresh application inventory still shows three blocked runs, one done run,
one queued run, no board executions, and no active processes/sessions/stages.
The owned developer shell is 44078, bundled BEAM 44186, healthy on loopback
52623. Inventory uses executable/PID/start identity, never raw arguments or
environments. Reuse the existing graceful restart path after verification.

All commands use RTK. Keep source tests, recorded-log diagnosis, native build
checks, and fresh provider acceptance distinct. No migration or dependency is
needed; final integration/restart evidence is pending.
