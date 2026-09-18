# Worklog — 1002 crash, power-loss, and sleep recovery drills

## Metadata

- Date/time (UTC): 2026-09-18
- Task: 1002
- Status: in progress
- Human/agent owner: codex
- Branch: `feature/1002-recovery-drills`
- Start revision: `c67200c`
- End revision: pending

## Acceptance criteria

- Exercise kill -9 during durable work, power-loss-style restart, quit during
  hibernate, and real sleep during every default workflow stage.
- Preserve evidence and measured sleep gaps while preventing duplicate stage,
  commit, push, or PR side effects.
- Record the fixture count and demonstrate at least 95% successful recovery.
- Attach drill logs and process/identity inspection evidence.

## Reference coding

- `rtk xerj search --prefix cuckoding-project-v7 -k 5 "recovery drill sleep
  stage duplicate commit pull request"` could not reach the loopback XERJ node.
- Directly inspected pinned MIT Agetor revision
  `eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a`,
  `src/cli/sse.ts:112-130`. Its abortable full-jitter reconnect delay is useful
  after a stream interruption. Cuckoding does not copy it here: the stricter
  boundary first records the sleep gap, extends leases, and performs one
  idempotent durable reconciliation before any adapter retry.

## Work performed

- Claimed Task 1002 and separated automatable crash/restart drills from the
  physical sleep/lid-close gate.
- Defined a fixed 26-observation denominator in `docs/RECOVERY_DRILLS.md`.
  Retries do not increase it, and any failed required row blocks acceptance.
- Tagged the existing root-cause regression scenarios instead of duplicating
  fixtures, and added a deterministic runner with per-case logs and JSON output.
- Made the physical verifier require an explicit default stage and write
  stage-specific evidence, preventing one generic sleep from being credited to
  all five workflow stages.
- Added a strict combined-evidence verifier for five software-sleep stages and
  one battery lid-close recovery.

## Verification

- `rtk proxy ruby spikes/1002-recovery-drills/run_automated.rb
  spikes/1002-recovery-drills/evidence/automated` — 20/20 observations passed;
  recovery rate 100%; exact output required `rtk proxy` for summary parsing.
- `rtk proxy ruby spikes/0004-sleep-wake-power/test_power_manager_spike.rb` —
  9 runs, 23 assertions, 0 failures.
- `rtk mix test test/cuckoding/execution/event_store_property_test.exs --seed
  109520` — 1 property, 0 failures after the first full-suite run encountered a
  transient SQLite `database is locked` error in that unrelated property.
- `rtk mix quality` — rerun passed: 10 properties, 202 tests, 0 failures;
  formatter, compilation with warnings as errors, Credo, Sobelow, and Hex audit
  clean. The expected crash-worker fixture logs are not failures.
- Physical five-stage sleep and battery lid-close evidence: pending explicit
  coordination on the test Mac.

## Handoff

Automated matrix complete. Do not complete or merge until the physical matrix
passes and `verify_evidence.rb` reports all 26 required observations.
