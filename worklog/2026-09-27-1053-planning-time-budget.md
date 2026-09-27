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

## Integration and running build

- `rtk git commit -m 'fix(planning): honor saved role time budgets'` created
  `cc48078`. `rtk git switch main` followed by
  `rtk git merge --ff-only fix/1053-planning-time-budget` integrated it locally
  without conflicts. No remote push.
- Used the existing `DeveloperRestart` helper through
  `rtk env -u GEM_HOME -u GEM_PATH /usr/bin/ruby -e ...`: verified the exact
  developer-bundle path, shell PID/start identity and owned descendants, sent
  graceful TERM to shell 44078, and verified all three descendants exited.
  No unrelated process was signalled and no force kill was used. Ruby's
  existing DBngin PATH-permission warning did not affect the operation.
- Standard-library SQLite `backup` from a read-only source produced a verified
  mode-0600 backup at
  `~/Library/Application Support/com.cuckoding.desktop/manual-backups/1053-20260927T050148Z/cuckoding.sqlite3`,
  SHA-256 `90cbfe4202e327870ce7b28b7b6415cd7223be8a4852e67d4e21907f258a0544`.
  Integrity and foreign-key checks passed. No data migration was needed.
- `rtk env -u CR_PAT ./bin/dev.build`: passed from clean main `cc48078`.
  Production assets, warnings-as-errors compilation, release assembly, metadata
  (6 tests/15 assertions), restart helper (6 tests/98 assertions), promotion,
  Rust formatting/10 tests/Clippy, and Tauri bundling passed. The sterile
  verifier passed bootstrap/token replay, authenticated browser handoff,
  diagnostics redaction, graceful cleanup, crash-before/after-READY, safe mode,
  and update backup/migration/rollback. Its database is disposable. Existing
  `rtk proxy` calls in build/restart helpers preserve subprocess semantics.
- `rtk ./bin/dev.restart`: passed. Fresh process inventory found exactly one
  developer shell, PID 54421 (2026-09-27 00:03:12 local), bundled BEAM PID 54506
  (00:03:13), and its child setup process. Health passed at
  `127.0.0.1:53976`. The running build is
  `desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`.
- `rtk python3 /tmp/cuckoding-1053-data-check.py`: integrity/FKs passed and all
  rows matched the backup for 2 projects, 2 boards, 17 tasks, 5 runs, 8 sessions,
  8 stage attempts, 8 proposals, and 22 migration records. Historical session
  grants and both failed planning runs are unchanged.
- Bundled BoardTaskIntake, Adapters, WalkingSkeleton, OrchestrationFailure,
  RunLive, and OutputParser BEAM files match the freshly compiled production
  release byte-for-byte. BoardTaskIntake SHA-256:
  `1d03e8a3512b02307cb92b25ef2da558f6144e4e44b28ae540f34f53968afdc9`;
  RunLive SHA-256:
  `c2dd83d22c0dc84fb3cfef00bc6725a9363c5b14fd8d4ed54c20f7aea226aab1`.
  The closing documentation commit does not change the source build.

## Handoff

Completed source fix, documentation, local integration, and developer-app
restart. Open Cuckoding through its menubar action, create a new planning run,
and verify the queued page shows the selected role's saved limit before
starting. This project's recorded Speculator limit is 60 minutes. Old failed
runs remain evidence; incomplete progress messages were not imported.

No new paid provider run, authenticated native visual inspection, physical
sleep/wake drill, signed clean-Mac acceptance, or remote publication is claimed.
All commands use RTK; recorded-run diagnosis, deterministic tests, and native
build verification are separate evidence. Final `rtk git diff --check` passed.
