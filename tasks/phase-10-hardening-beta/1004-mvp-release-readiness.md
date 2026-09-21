# 1004 — Complete MVP Release Readiness

```yaml
status: in_progress
owner: codex
started_at: 2026-09-21
worklog: worklog/2026-09-21-1004-release-readiness.md
```

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
- [x] Automatic raw-metric pruning preserves measurements needed by an
  unfinished stage; focused eight-day regression passes.
- [x] Synthetic missed-minute catch-up is bounded, restart-safe, and prevents
  raw pruning until minute and stage aggregates exist.
- [ ] Verify effective retention and consent/default behavior in a signed
  enrollment build.

## Acceptance criteria

- [ ] Every gate has current evidence tied to the artifact.
- [ ] Documentation matches shipped behavior.

## Verification and evidence

Use the signed release candidate on a clean machine; execute the critical journey and recovery drills; attach the evidence index.
