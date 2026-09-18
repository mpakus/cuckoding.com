# Worklog — 1002 crash, power-loss, and sleep recovery drills

## Metadata

- Date/time (UTC): 2026-09-18
- Task: 1002
- Status: complete
- Human/agent owner: codex
- Branch: `feature/1002-recovery-drills`
- Start revision: `c67200c`
- End revision: recorded by the Task 1002 closing commit

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
- Defined a fixed 27-observation denominator in `docs/RECOVERY_DRILLS.md`.
  Retries do not increase it, and any failed required row blocks acceptance.
- Tagged the existing root-cause regression scenarios instead of duplicating
  fixtures, and added a deterministic runner with per-case logs and JSON output.
- Made the physical verifier require an explicit default stage and write
  stage-specific evidence, preventing one generic sleep from being credited to
  all five workflow stages.
- Added a strict combined-evidence verifier for five software-sleep stages and
  one battery lid-close recovery.
- Hardened the opt-in physical verifier to darken the display before software
  sleep, discard malformed `pmset` bytes, and avoid racing the clamshell sensor
  while still requiring a scoped `Clamshell Sleep` record.

## Verification

- `rtk proxy ruby spikes/1002-recovery-drills/run_automated.rb
  spikes/1002-recovery-drills/evidence/automated` — 21/21 observations passed;
  recovery rate 100%; exact output required `rtk proxy` for summary parsing.
- `rtk proxy ruby spikes/0004-sleep-wake-power/test_power_manager_spike.rb` —
  10 runs, 24 assertions, 0 failures.
- `rtk mix test test/cuckoding/execution/event_store_property_test.exs --seed
  109520` — 1 property, 0 failures after the first full-suite run encountered a
  transient SQLite `database is locked` error in that unrelated property.
- Final `rtk mix quality` — 10 properties, 202 tests, 0 failures;
  formatter, compilation with warnings as errors, Credo, Sobelow, and Hex audit
  clean. The expected crash-worker fixture logs are not failures.
- Real sleep gaps passed for `specification` (73,505 ms), `development`
  (12,729 ms), `qa` (26,774 ms), `human_approval` (4,134 ms), and
  `release_handoff` (28,070 ms). Every row recorded one stage execution, one
  reconciliation event, and a live loopback service/stream.
- The final battery run recorded `Clamshell Sleep`, a 124,711 ms first-tick
  gap, a missing worker recovered once, one stage execution, and surviving
  loopback service/stream. An earlier battery run was rejected because macOS
  recorded `Idle Sleep`; retries did not change the denominator.
- `rtk proxy ruby spikes/1002-recovery-drills/verify_evidence.rb
  spikes/1002-recovery-drills/evidence` — 27/27, 100%, target met.
- Rejected attempts remain excluded: one `human_approval` request and one
  `release_handoff` retry never slept; an earlier release sleep exposed
  malformed `pmset` bytes before the scoped-log parser was hardened.

## Handoff

Complete. All required automated, stage-sleep, and battery-clamshell rows pass.
External provider CLIs still own their native session-resume semantics.
