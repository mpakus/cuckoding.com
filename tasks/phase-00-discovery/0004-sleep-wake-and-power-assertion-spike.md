# 0004 — Sleep/Wake Detection and Power Assertion Spike

```yaml
status: review
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
- [x] Simulated gap detected with correct duration; real gap pending coordination.
- [x] Simulated agent process alive after wake → continues; killed during sleep → recovered.
- [x] Simulated provider HTTP stream drop classified as transient.
- [ ] Battery + lid close behavior documented honestly.

## Acceptance criteria

- [ ] Simulated and real gaps are detected within one tick. Simulated passes; real sleep is pending.
- [x] No duplicate stage execution after simulated wake in the spike.
- [x] Assertion lifecycle is correct.

## Verification and evidence

Attach `pmset` logs, timeline of events, and process inspection before/after sleep.

Safe automated evidence is under `spikes/0004-sleep-wake-power/evidence/` and summarized in `docs/SLEEP_WAKE_POWER_SPIKE.md`. Task remains in review until a coordinated real-sleep and AC/battery lid-close window supplies the remaining evidence.

Discovery correction: macOS 27 `CLOCK_MONOTONIC` continues while asleep. ADR-022 replaces the proposed wall/monotonic detector with continuous-monotonic versus `CLOCK_UPTIME_RAW` divergence.
