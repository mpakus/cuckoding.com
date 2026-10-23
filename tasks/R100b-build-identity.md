# R100b — Identify the actual local build

Status: implemented and verified, 2026-10-23; local integration pending.

- [x] Generate one bounded public build manifest with UUID/date, source revision,
  dirty observation, digest of enumerated application inputs, tool versions,
  target and schema. Ignore generated output and never read unrelated user files.
  Refuse linked/special inputs and changed inputs during the build.
- [x] Bind the packaged Phoenix release and native shell to that exact manifest
  before data migration/dispatch. Source development explicitly has no packaged
  identity. Expose only the public build observation in authenticated Settings.
- [x] Retain a private immutable build receipt with actual helper/resource-manifest
  hashes after strict/deep seal verification. No claim of Developer ID,
  notarization, reproducibility or release acceptance from an ad-hoc preview.
- [x] Test malformed/mixed/missing identities, source drift and output/path guards;
  verify source UI, native launch, build/smoke and preserved data. Update
  docs/AGENTS/README.
- [ ] Merge locally to main and delete the feature branch.

Provider/physical/clean-machine/signing/update acceptance remains separate.
Evidence: [worklog](../worklog/2026-10-23-R100b-build-identity.md).
