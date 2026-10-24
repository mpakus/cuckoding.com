# R050l — Exercise real offline toolchains through isolated check transport

Status: verified locally, 2026-10-23. Base `07100fb`.

- [x] Pin official Linux toolchain inputs and observed runtime versions; never
  borrow host toolchains/profiles or silently substitute versions. Keep image
  provenance/packaging acceptance separate from local synthetic proof.
- [x] Build a fresh private candidate fixture in the protected guest. Separate
  worker output from privileged control; bind request/candidate/toolchain IDs,
  exact command, exit/output and native shutdown in the retained observation.
- [x] Run actual npm and Mix pass/fail checks without guest network/host shares.
  Exercise forged output/control access, cancellation or lost owner where
  applicable; missing native proof must not become a passing check.
- [x] Keep shipping check grants unchanged until production transport/ownership/
  OTP/receipt/UI integration is verified. Update docs/AGENTS/README, relevant
  regressions and evidence; merge local main without publication.

The beta's full toolchain feature remains required. This slice must produce
actual command results rather than another stand-in workload or fabricated pass.

Ten actual guest cases, nine decoder lifecycle cases with 21 invalid-field
variants each, and all five lifetime/four watchdog regressions passed locally.
See [worklog](../worklog/2026-10-23-R050l-offline-toolchain-checks.md). This is
prerequisite evidence; the production toolchain feature remains unfinished.
