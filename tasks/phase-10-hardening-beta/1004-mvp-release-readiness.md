# 1004 — Complete MVP Release Readiness

## Objective

Re-run the MVP definition of done, freeze supported versions, validate installers/updater, finalize onboarding and limitations (including host-runner isolation limits), assign support and incident owners, and make the go/no-go decision..

## Dependencies

- 1003.

## Scope

Re-run the MVP definition of done, freeze supported versions, validate installers/updater, finalize onboarding and limitations (including host-runner isolation limits), assign support and incident owners, and make the go/no-go decision.

## Deliverables

- Release-readiness report and decision.
- Support matrix, limitations, onboarding, privacy/data, backup/recovery, troubleshooting docs.
- Release notes, checksums, SBOM, provenance, rollback plan.

## Checklist

- [ ] Every item in `docs/PLAN.md` definition of done re-run.
- [ ] Diagnostics/telemetry consent and retention defaults confirmed.

## Acceptance criteria

- [ ] Every gate has current evidence tied to the artifact.
- [ ] Documentation matches shipped behavior.

## Verification and evidence

Use the signed release candidate on a clean machine; execute the critical journey and recovery drills; attach the evidence index.
