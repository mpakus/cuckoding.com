# 0601 — Normalized Activity Event Stream

## Objective

Persist and broadcast normalized public activity events with the full correlation chain, redaction, sequence numbers, reconnect catch-up, and stale/reconciling indicators..

## Dependencies

- 0504.

## Scope

Persist and broadcast normalized public activity events with the full correlation chain, redaction, sequence numbers, reconnect catch-up, and stale/reconciling indicators.

## Deliverables

- Event pipeline and LiveView stream component.

## Checklist

- [ ] Persist before broadcast.
- [ ] Reconnect fetches after last acknowledged sequence.
- [ ] Sleep gaps rendered on timelines.

## Acceptance criteria

- [ ] No event lost or duplicated across reconnects.

## Verification and evidence

Run reconnect and ordering tests.
