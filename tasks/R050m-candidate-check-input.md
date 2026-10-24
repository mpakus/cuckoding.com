# R050m — Native candidate transport for isolated checks

Status: verified locally, base `b7cd25f`, 2026-10-23.

- [x] Add fixed native prepare/verify operations for a bounded, deterministic
  newc input archive from an exact retained prepared candidate.
- [x] Reuse repository/ownership/index/raw-byte checks; copy immutable Git blobs,
  never host shares, Git administration, uncommitted or arbitrary files. Bind
  request/source/preparation/head/tree, manifest and archive hashes.
- [x] Exclusively retain private intent/artifacts/receipt; use descriptor-relative
  creation and refuse aliases, changed/foreign inputs, replay, partial artifacts
  and lost cancellation/deadline authority. Verification is read-only.
- [x] Add closed host projections and meaningful native/host regressions, update
  docs/AGENTS/README, verify and merge local main without publication.

This implements production candidate transport, not another workload probe.
It does not yet enable VM checks or change Start permissions; image installation,
guest execution/ownership, frozen grants and OTP/UI integration remain required.

The sealed local-preview app passed nine candidate-input CLI operations, fourteen
existing combination operations and both packaged recovery cases. Five focused
native cases and host projection tests cover the transport; see the
[worklog](../worklog/2026-10-23-R050m-candidate-check-input.md) for full-suite scope.
