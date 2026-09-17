# 0004 — Sleep/Wake Detection and Power Assertion Spike

## Objective

Prototype the Power Manager: hold an idle-sleep assertion via a supervised `caffeinate -i -w <pid>` (and evaluate an IOKit assertion from the shell), detect sleep gaps by comparing monotonic and wall clocks, and reconcile a running agent process after a real sleep (`pmset sleepnow`) and after a lid close on AC and on battery..

## Dependencies

- 0002.

## Scope

Prototype the Power Manager: hold an idle-sleep assertion via a supervised `caffeinate -i -w <pid>` (and evaluate an IOKit assertion from the shell), detect sleep gaps by comparing monotonic and wall clocks, and reconcile a running agent process after a real sleep (`pmset sleepnow`) and after a lid close on AC and on battery.

## Deliverables

- Spike module and measurements.
- Behavior table: what survives sleep (processes, provider streams, dev server, ports).
- Decision on assertion mechanism and detection thresholds (ADR-016 confirmation).

## Checklist

- [ ] Assertion visible in `pmset -g assertions` only while active.
- [ ] Gap detected with correct duration.
- [ ] Agent process alive after wake → continues; killed during sleep → recovered.
- [ ] Provider HTTP stream drop classified as transient.
- [ ] Battery + lid close behavior documented honestly.

## Acceptance criteria

- [ ] Simulated and real gaps are detected within one tick.
- [ ] No duplicate stage execution after wake in the spike.
- [ ] Assertion lifecycle is correct.

## Verification and evidence

Attach `pmset` logs, timeline of events, and process inspection before/after sleep.
