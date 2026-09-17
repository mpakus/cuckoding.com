# 0306 — Power Assertions and Sleep/Wake Reconciliation

## Objective

Implement the Power Manager: assertion lifecycle, sleep-gap detection, `power_events`, wake reconciliation hooks into leases, adapters, ports, and dev servers, unattended mode window, and timeline events..

## Dependencies

- 0305.
- 0004 findings.

## Scope

Implement the Power Manager: assertion lifecycle, sleep-gap detection, `power_events`, wake reconciliation hooks into leases, adapters, ports, and dev servers, unattended mode window, and timeline events.

## Deliverables

- Power Manager module.
- Reconciliation integration and events.
- Settings for assertion behavior.

## Checklist

- [ ] Assertion held only while needed.
- [ ] Gap recorded with duration.
- [ ] Heartbeats inside gaps are `sleep_gap`.
- [ ] Unattended mode never bypasses approvals.

## Acceptance criteria

- [ ] Simulated gap test passes.
- [ ] Real sleep drill (opt-in) passes with single stage execution.

## Verification and evidence

Run simulated gap tests; execute the real sleep drill on a test machine and attach logs.
