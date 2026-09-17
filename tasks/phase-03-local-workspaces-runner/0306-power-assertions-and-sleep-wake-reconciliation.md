# 0306 — Power Assertions and Sleep/Wake Reconciliation

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0306-power-manager.md
```

## Objective

Implement the Power Manager: assertion lifecycle, sleep-gap detection, `power_events`, wake reconciliation hooks into leases, adapters, ports, and dev servers, unattended mode window, and timeline events.

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

- [x] Assertion held only while needed.
- [x] Gap recorded with duration.
- [x] Heartbeats inside gaps are `sleep_gap`.
- [x] Unattended mode never bypasses approvals.

## Acceptance criteria

- [x] Simulated gap test passes.
- [x] Real sleep drill (opt-in) passes with single stage execution.

## Verification and evidence

Run simulated gap tests; execute the real sleep drill on a test machine and attach logs.
