# Run recovery integration regression

- Scope: one real-pool regression for Repo loss during a fake Codex task run;
  isolated writer branch `codex/boss-run-recovery-tests`, baseline `32107a6`.
  Only `test/boss/run_recovery_test.exs` and this log are owned here. Root owns
  shared documentation, final combined checks and integration.
- RTK, Ponytail, TDD and Git workflow skills applied. Elixir1.20.3/OTP28 verified.
- xerj query `ConfigureTreeCancellation terminate process group`; inspected
  `examples/agent-orchestrator/backend/internal/process/tree_unix.go` at
  Apache-2.0 snapshot `7193eff4e08f1481944845ee058fe6fd18930b6d`.
  Adopted observable group cleanup as acceptance; rejected direct leader-only
  proof and cached-PID recovery signals. No reference code copied.
- Test uses an exclusively created scratch DB with a real two-connection pool,
  actual Worker/Workspace/native guardian, and a local Python fake CLI with
  a TERM-ignoring child. No provider/network calls. Retained edits, unchanged
  task/source, conservative quarantine, replay and no respawn are asserted.
- `rtk proxy asdf exec mix test test/boss/run_recovery_test.exs`: 1 passed,
  1.3s, seed493447. Formatter passed for the owned test.
- Mutation evidence: an exclusively created temporary test recompiled Manager
  in memory with Repo-DOWN handling changed to `{:noreply, state}`. The new test
  failed at its Manager-DOWN assertion after3000ms (seed885008); no tracked
  runtime source or compiled BEAM file was edited. The real implementation
  restores this ownership boundary on the subsequent normal run.
- Final combined application/browser checks remain root-owned. No provider call
  was made; this proves local lifecycle/recovery, not live model access or Done.
- Final owned check: `rtk proxy asdf exec mix format --check-formatted
  test/boss/run_recovery_test.exs` passed; `rtk proxy asdf exec mix test
  test/boss/run_recovery_test.exs test/boss/run_persistence_test.exs` passed7/7
  in4.0s, seed948380. Next: root merges this test branch, integrates the native
  writer's separate launch-gate follow-up and runs combined acceptance.
