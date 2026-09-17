# 0602 — Host Resource Metrics and Rollups

## Objective

Collect CPU, RSS, process count, and open ports per process group at 2–5 seconds; roll up to 1-minute and stage; treat missing samples as missing; label host-runner limits as unenforced..

## Dependencies

- 0302.

## Scope

Collect CPU, RSS, process count, and open ports per process group at 2–5 seconds; roll up to 1-minute and stage; treat missing samples as missing; label host-runner limits as unenforced.

## Deliverables

- Sampler, rollup jobs, retention.

## Checklist

- [ ] Active vs wall time in rollups.
- [ ] No interpolation.

## Acceptance criteria

- [ ] Attribution to the correct session in tests.

## Verification and evidence

Run sampler and rollup tests.
