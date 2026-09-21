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
- [x] Audit all ten definition-of-done criteria against source, drill, beta,
  and release-artifact evidence; reopen any checkbox whose proof is narrower
  than its product-level wording.
- [ ] Diagnostics/telemetry consent and retention defaults confirmed.
- [x] Automatic raw-metric pruning preserves measurements needed by an
  unfinished stage; focused eight-day regression passes.
- [x] Synthetic missed-minute catch-up is bounded, restart-safe, and prevents
  raw pruning until minute and stage aggregates exist.
- [x] Source-grounded MVP boundary, README, and beta-ledger disclosures agree
  on implemented adapters, credential locations, and actual retention behavior.
- [x] Publish a current-source support/onboarding/privacy/recovery guide and
  explicit no-go decision without calling it signed-release acceptance.
- [x] Require the official release job to pass `mix quality` before it imports
  signing/notary secrets; the first manual CI run exposed an installed-CLI test
  assumption, and the corrected rerun passed all 288 tests/10 properties before
  value-free preflight refused five absent Apple secrets. Signed release open.
- [x] Repair non-resolving pinned release action SHAs and verify all workflow
  action refs against their upstream commits; actual job execution remains open.
- [x] Verify the macOS runner architecture and report missing release
  configuration names before certificate import; no secrets are provisioned.
- [x] Document how the stakeholder can provision the five missing CI secrets
  without committing or disclosing values; actual provisioning is pending.
- [x] Rebuild the current-source unsigned app and re-run local source quality;
  correct the event-sequence test wait to cover the bounded SQLite retry window.
- [x] Sign and notarize the current local app with existing Keychain credentials;
  verify the embedded release after signing. Full release artifacts and clean-Mac
  enrollment remain open.
- [x] Create a separate post-staple ZIP and verify its quarantined extracted app
  on the same Mac; record the ZIP digest without replacing the older distribution.
- [x] Repeat the isolated build, local Developer ID signing/notarization, and
  quarantined post-staple ZIP verification for current `17d367a`; preserve the
  older distribution and do not count this as updater or clean-Mac acceptance.
- [x] Stage the checksum-matched current ZIP for the existing QA account; its
  actual launch, account-data check, and clean-Mac test remain open.
- [ ] Approve and verify the output/artifact retention policy and participant
  disclosure; no automatic age purge exists for full redacted artifacts yet.
- [ ] Verify effective retention and consent/default behavior in a signed
  enrollment build.

## Acceptance criteria

- [ ] Every gate has current evidence tied to the artifact.
- [ ] Documentation matches shipped behavior.

## Verification and evidence

Use the signed release candidate on a clean machine; execute the critical journey and recovery drills; attach the evidence index.
