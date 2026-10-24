# R060t — Read complete retained guest-check proof

Implemented and verified, base `ae041a3`, 2026-10-24. Local integration only.
[Evidence](../worklog/2026-10-24-R060t-retained-guest-check.md).

- [x] Add a fixed read-only native recovery primitive for the exact run/check/
  attempt/candidate/image binding, requiring complete existing admission,
  intent, keeper publication and wrapper receipt. Never launch a VM, reconstruct
  missing evidence, modify artifacts or infer closure from process absence.
- [x] Verify descriptor-pinned private files, source and owned candidate input,
  image/keeper/output hashes, exact original request and typed VM/group closure.
  Keep a separate 60-second inspection budget and original execution deadlines.
- [x] Preserve bounded private failure feedback and public metadata separation;
  reject altered, linked, missing, foreign, cancelled or uncertain proof. Prove
  repeated reads leave evidence/source/index unchanged with actual guest results.
- [x] Run focused/full native checks, source quality, build/package smoke and
  synthetic actual-VM proof. Update docs/AGENTS/README and merge local main.

This prerequisite supplies native inspection only. The subsequent OTP recovery
consumer must freeze new Start authority, retain Interrupted attempts and dated
observations, require all original checks, pause for explicit Resume and preserve
review/deadline/control gates. Current workflows remain interrupted until that
consumer is implemented; this task does not itself recover or accept lost work.

Real providers, dependencies/platform support, hard keeper loss, physical sleep
and release acceptance remain open.
