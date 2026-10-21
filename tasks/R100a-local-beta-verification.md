# R100a — Current local beta artifact verification

Status: complete, 2026-10-21. Local preview verification only; broader R100 gates
remain open. [Evidence](../worklog/2026-10-21-R100a-local-beta-verification.md).

- [x] Rebuild the current macOS app only after owned-instance inspection; run the
  packaged smoke and native regression suite against this artifact/toolchain.
- [x] Seal the complete ad-hoc development bundle, require strict verification
  before smoke, and prove changed resources fail verification on a disposable copy.
- [x] Verify forward schema upgrade and local session/dashboard behavior in a
  recognized isolated data root; preserve every previous workspace/profile.
- [x] Record concrete live-account, signing, clean-machine and recovery gates;
  never count fixture/build success as provider or public-release acceptance.
- [x] Update docs/AGENTS/README and verification worklog; merge local main only,
  no publication or reset of user data.
