# 0004 — Sleep/Wake Detection and Power Assertion Spike

```yaml
status: done
owner: codex
started_at: 2026-09-17
worklog: worklog/2026-09-17-0004-sleep-wake-power-spike.md
```

## Objective

Prototype the Power Manager: hold an idle-sleep assertion via a supervised `caffeinate -i -w <pid>` (and evaluate an IOKit assertion from the shell), detect sleep gaps by comparing monotonic and wall clocks, and reconcile a running agent process after a real sleep (`pmset sleepnow`) and after a lid close on AC and on battery.

## Dependencies

- 0002.

## Scope

Prototype the Power Manager: hold an idle-sleep assertion via a supervised `caffeinate -i -w <pid>` (and evaluate an IOKit assertion from the shell), detect sleep gaps by comparing monotonic and wall clocks, and reconcile a running agent process after a real sleep (`pmset sleepnow`) and after a lid close on AC and on battery.

## Deliverables

- Spike module and measurements.
- Behavior table: what survives sleep (processes, provider streams, dev server, ports).
- Decision on assertion mechanism and detection thresholds (ADR-016 confirmation).

## Checklist

- [x] Assertion visible in `pmset -g assertions` only while active.
- [x] Simulated and real software-sleep gaps detected with correct duration.
- [x] Simulated agent process alive after wake → continues; killed during sleep → recovered.
- [x] Simulated provider HTTP stream drop classified as transient.
- [x] Battery + lid close behavior documented honestly.

## Acceptance criteria

- [x] Simulated and real software-sleep gaps are detected within one tick.
- [x] No duplicate stage execution after simulated wake in the spike.
- [x] Assertion lifecycle is correct.

## Verification and evidence

Attach `pmset` logs, timeline of events, and process inspection before/after sleep.

Safe automated, coordinated software-sleep, and physical lid-close evidence is under `spikes/0004-sleep-wake-power/evidence/` and summarized in `docs/SLEEP_WAKE_POWER_SPIKE.md`.

Five approved `pmset sleepnow` attempts were made on 2026-09-17. One sleep occurred only after the verifier had already cleaned up; four were cancelled during sleep preparation by new user-activity assertions. None is accepted as real recovery evidence. See `spikes/0004-sleep-wake-power/evidence/real-sleep-attempts.md`.

A sixth approved attempt succeeded after `pmset displaysleepnow`: the first resumed tick measured an 11,549 ms gap, the disposable worker, loopback server, port, and provider stream survived, the assertion was reacquired, and reconciliation retained one stage execution with one event. See `real-sleep-summary.json`, `real-sleep-clocks.json`, and the scoped `real-sleep-pmset.log` in the evidence directory.

Physical lid-close drills also passed. On AC, a 4,096 ms gap was detected while the worker, stream, server, port, and existing idle assertion survived. On battery, a 121,169 ms gap was detected; a worker-loss deadline fell inside the recorded sleep interval, its termination ran immediately after CPU resume, and first reconciliation recovered the missing worker exactly once without duplicating the stage. See the `lid-close-*` evidence files.

Discovery correction: macOS 27 `CLOCK_MONOTONIC` continues while asleep. ADR-022 replaces the proposed wall/monotonic detector with continuous-monotonic versus `CLOCK_UPTIME_RAW` divergence.
