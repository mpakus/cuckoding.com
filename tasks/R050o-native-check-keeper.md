# R050o — Production native guest check keeper

Status: completed and verified, base `7f8a9e1`, 2026-10-24.

- [x] Package an exact dedicated Swift/Virtualization keeper, with its own
  entitlement and no new shell entitlement or inherited environment.
- [x] Add fixed native execution consuming verified image/candidate receipts,
  bounded literal checks and an original deadline. Retain private intent/artifacts;
  reject foreign/tampered/replayed scope before VM effects.
- [x] Require actual SDK Stopped plus owned helper cleanup before publishing
  bounded public results. EOF/cancellation/expiry must stop, never invent an exit;
  missing closure remains unverified. Separate captured output from authority.
- [x] Exercise actual packaged checks, cancellation and adverse protocol/storage
  cases; update docs/AGENTS/README, verify and merge local main only.

The existing check normalizer/Start grant remains unchanged. Next integrate this
native primitive with supervised OTP admission and the single Arena Start.

[Verification and final local artifact](../worklog/2026-10-24-R050o-native-check-keeper.md).
