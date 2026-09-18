# Worklog — 0902 release signing and notarization

## Metadata

- Date/time (UTC): 2026-09-18
- Task: 0902
- Status: in progress
- Human/agent owner: codex
- Branch: `feature/0902-release-signing-notarization`
- Start revision: `88f0182`
- End revision: pending

## Acceptance criteria

- Build a distributable macOS app that embeds ERTS and needs no system Erlang
  or Elixir runtime.
- Sign every nested Mach-O inside-out with hardened runtime, applying only the
  entitlements needed by the BEAM runtime, and verify every signature.
- Produce a notarized and stapled artifact accepted by Gatekeeper on a clean
  supported Mac.
- Generate an SBOM, SHA-256 checksums, and build provenance beside the release
  artifact through a repeatable CI pipeline.

## Reference coding

- Focused project and pinned-peer XERJ searches were attempted first; the
  configured loopback node was unavailable.
- The local Task 0003 spike defines the bundle-specific boundary at
  `docs/MENUBAR_SHELL_SPIKE.md`: sign nested ERTS executables and NIFs
  inside-out, start with the least BEAM JIT entitlement, and verify signing,
  Gatekeeper, notarization, stapling, and clean launch.
- Apple's current notarization guidance requires Developer ID signing, secure
  timestamps, hardened runtime, `notarytool`, review of the notarization log,
  and a stapled ticket. Tauri's current macOS distribution guidance confirms
  the Developer ID identity and hardened-runtime configuration points.
- The host has one valid Developer ID Application identity. No credentials are
  copied into the repository or agent environment. The expected local
  `notarytool` Keychain profile is not present, so notarization submission is a
  known external gate after the signed artifact is ready.

## Work performed

- Claimed Task 0902 and restated its release and evidence gates.
- Added inside-out signing based on actual Mach-O magic bytes, not filename
  extensions. The script rejects interrupted codesign leftovers, grants only
  `allow-jit` to `beam.smp`, applies hardened runtime and secure timestamps,
  verifies every native signature, and requires matching Developer ID Team IDs.
- Added notarization by Keychain profile or a mode-0400/0600 App Store Connect
  key file, mandatory submission-log capture and zero-issue validation,
  stapling, ticket validation, and Gatekeeper assessment.
- Added a clean-worktree release orchestrator plus a CycloneDX 1.6 SBOM for the
  target's bundled OTP/Hex/Rust components, package licenses where declared,
  source/lockfile provenance, and SHA-256 checksums.
- Added a least-privilege GitHub Actions release workflow. All reusable actions
  are pinned to immutable commits; certificate and notarization secrets are
  scoped to their consuming steps, and the temporary private key is removed on
  success or failure.
- Documented local and CI credential boundaries and made the existing sterile
  verifier accept an explicit bundled-release path so the signed artifact can
  exercise the same 22 protocol and cleanup checks.

## Verification

| Check | Result |
| --- | --- |
| Shell and system-Ruby syntax | pass |
| Release helper regression tests | pass; 3 runs, 7 assertions |
| Workflow YAML parsing | pass with system Ruby and `YamlElixir` |
| SBOM/provenance/checksum fixture | pass; 291 target components, 275 with declared licenses; all three checksums verified |
| Ad-hoc nested signing rehearsal | pass; all 25 Mach-O signatures, hardened-runtime flags, deep bundle seal, and BEAM JIT entitlement verified |
| Ad-hoc bundled runtime | expected rejection; hardened library validation rejects NIFs because ad-hoc signatures have no Team ID; no weakening entitlement was added |
| `rtk proxy sh desktop/build.sh` | pass; 4 Rust tests and all 22 sterile release checks passed |
| `rtk mix quality` | pass; 10 properties and 185 tests, 0 failures; Credo, Sobelow, and dependency audit passed |
| Developer ID signing | blocked at the macOS Keychain approval dialog before the first signature completed |
| Apple notarization and Gatekeeper | blocked; the `Cuckoding` notary profile is not present |

`rtk proxy` was used where exact build, signing, notarization, or subprocess
output is operationally required. GitHub Actions has one unavoidable bootstrap
command to install RTK; every subsequent workflow shell command uses RTK.

## Handoff

In progress. Approve the pending `codesign` Keychain request with **Always
Allow**, then create the `Cuckoding` profile interactively with `xcrun
notarytool store-credentials Cuckoding` so no password enters command history.
No signed artifact is treated as notarized or Gatekeeper-ready until Apple
accepts it, the ticket is stapled and validated, and the installed artifact
passes the clean-Mac check.
