# 0603 — Usage, Cost, and Confidence Accounting

## Objective

Implement usage records with source/confidence, versioned price catalogs, estimated cost with formula recording, and plugin optimization records as separate dimensions..

## Dependencies

- 0402 or 0403.

## Scope

Implement usage records with source/confidence, versioned price catalogs, estimated cost with formula recording, and plugin optimization records as separate dimensions.

## Deliverables

- Cost calculator, catalog versions, UI labels.

## Checklist

- [ ] Provider-reported preferred; `≈` for estimates.
- [ ] Never infer subscription marginal cost.

## Acceptance criteria

- [ ] Cost reconciles with fixtures within documented limits.

## Verification and evidence

Run cost formula tests with frozen catalogs.
