# Recovery Drills

Task 1002 uses named scenario observations rather than retries as the recovery
rate denominator. A retry updates the evidence for the same observation; it
never increases the denominator. Every required scenario must pass, even when
the aggregate result would otherwise remain at or above 95%.

## Automated matrix

Run from the repository root:

```sh
rtk proxy ruby spikes/1002-recovery-drills/run_automated.rb \
  spikes/1002-recovery-drills/evidence/automated
```

The runner executes only tests tagged `recovery_drill`, the power-contract unit
suite, and the non-sleeping process verifier. It writes one log per case and a
machine-readable `summary.json`. `rtk proxy` is intentional here because the
runner parses the exact ExUnit and Minitest summaries.

The 20 automated observations cover surviving and interrupted processes,
lease-first sleep reconciliation, a process killed during an open SQLite
transaction, retry of a failed wake pass, real `caffeinate` ownership, durable
hibernate/resume, quit-time hibernation, and one idempotent commit/push release.

## Physical matrix

Physical runs are opt-in because they sleep the Mac. Run them only on a quiet
or locked test Mac with a coordinated wake plan. Each command creates distinct
stage-named evidence and must report `stage_execution_count: 1`, exactly one
reconciliation event, a positive `detected_gap_ms`, and a surviving or
reconnected loopback fixture.

```sh
rtk proxy ruby spikes/0004-sleep-wake-power/power_manager_spike.rb --real-sleep specification spikes/1002-recovery-drills/evidence/physical
rtk proxy ruby spikes/0004-sleep-wake-power/power_manager_spike.rb --real-sleep development spikes/1002-recovery-drills/evidence/physical
rtk proxy ruby spikes/0004-sleep-wake-power/power_manager_spike.rb --real-sleep qa spikes/1002-recovery-drills/evidence/physical
rtk proxy ruby spikes/0004-sleep-wake-power/power_manager_spike.rb --real-sleep human_approval spikes/1002-recovery-drills/evidence/physical
rtk proxy ruby spikes/0004-sleep-wake-power/power_manager_spike.rb --real-sleep release_handoff spikes/1002-recovery-drills/evidence/physical
```

The battery drill additionally proves that a missing worker resumes once after
lid close. Disconnect external power and confirm `pmset -g batt` says battery
power before running it. Close the lid within ten seconds, leave it closed for
at least sixty seconds, then reopen it:

```sh
rtk proxy ruby spikes/0004-sleep-wake-power/power_manager_spike.rb --lid-close battery recover development spikes/1002-recovery-drills/evidence/physical
```

The combined denominator is 26: 20 automated observations, five default-stage
sleep observations, and one battery lid-close recovery. The target is at least
95%, but a missing or failed required row still blocks acceptance. Physical
evidence is a host-specific release gate and must not be inferred from the
earlier Task 0004 measurements.

After all six physical observations, validate the artifacts and produce the
combined report:

```sh
rtk proxy ruby spikes/1002-recovery-drills/verify_evidence.rb \
  spikes/1002-recovery-drills/evidence
```

## Evidence review

For every physical summary, check:

- `stage_key` matches the requested stage;
- `detected_on_first_tick` is `true` and `detected_gap_ms` is positive;
- `stage_execution_count` is `1` and there is one reconciliation event;
- live mode reports `worker_survived`; recover mode reports
  `worker_recovered` and one replacement provider session;
- the server, port, and provider stream survived or reconnected;
- the matching scoped `pmset` log records the same sleep/wake cycle.

Do not count cancelled sleep requests, pre-sample sleeps, or repeated attempts.
Keep failed evidence with its log and replace only the status of that named row
after a successful rerun.
