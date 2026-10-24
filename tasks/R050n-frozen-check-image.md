# R050n — Production check image and protected guest control

Status: verified locally, base `ae7b73c`, 2026-10-23/24.

- [x] Implement a fixed native image installer from pinned upstream kernel/
  runtime inputs, private exclusive storage and a bound manifest/receipt.
- [x] Build production guest entry/control/worker programs consuming R050m input,
  fixed toolchain selection and bounded literal argv. Enforce unprivileged
  resource groups, separate control/output, source integrity and closure.
- [x] Exercise actual native image creation and guest npm/Mix checks from native
  candidate archives, including malformed/tampered/cancelled/failing cases.
- [x] Keep Start disabled for this new grant until native keeper/OTP integration
  is complete; update docs/AGENTS/README, verify and merge local main only.

This is production image/runtime code. Synthetic tests do not establish real
project dependency, provider, physical-sleep or distribution acceptance.

The sealed local-preview helper produced/verified the actual image and passed
eleven VM cases, including output limits and active cancellation. Existing native
candidate transport and packaged recovery remain verified. See the
[worklog](../worklog/2026-10-23-R050n-frozen-check-image.md) for artifact identities,
failed attempts, full-suite scope and the existing native dependency warnings.
