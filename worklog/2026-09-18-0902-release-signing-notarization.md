# Worklog — 0902 release signing and notarization

## Metadata

- Date/time (UTC): 2026-09-18
- Task: 0902
- Status: complete
- Human/agent owner: codex
- Branch: `feature/0902-release-signing-notarization`
- Start revision: `88f0182`
- End revision: task commit

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
  copied into the repository or agent environment. The human created and
  validated the `Cuckoding` `notarytool` Keychain profile interactively.

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
- Diagnosed the first notarized artifact's clean launch failure to OTP crypto
  loading Homebrew's external `libcrypto`. The build now embeds that one native
  dependency, rewrites both affected NIFs to `@loader_path`, ad-hoc signs the
  rewritten binaries for local verification, and rejects any remaining
  non-system absolute dependency. Developer ID signing replaces the ad-hoc
  signatures for release.
- Added bundled OpenSSL provenance to the SBOM and made pre-readiness verifier
  failures retain bounded runtime output so native launch defects are directly
  actionable.

## Verification

| Check | Result |
| --- | --- |
| Shell and system-Ruby syntax | pass |
| Release helper regression tests | pass; 4 runs, 10 assertions |
| Workflow YAML parsing | pass with system Ruby and `YamlElixir` |
| Final SBOM, provenance, and checksums | pass; 292 target components including OpenSSL 3.6.3; post-signing binary digest present; clean source revision `32fb8fb`; all three checksums verified |
| Ad-hoc nested signing rehearsal | pass; all 25 Mach-O signatures, hardened-runtime flags, deep bundle seal, and BEAM JIT entitlement verified |
| Ad-hoc bundled runtime | expected rejection; hardened library validation rejects NIFs because ad-hoc signatures have no Team ID; no weakening entitlement was added |
| `rtk proxy sh desktop/build.sh` | pass; 4 Rust tests and all 22 sterile release checks passed |
| `rtk mix quality` | pass; 10 properties and 185 tests, 0 failures; Credo, Sobelow, and dependency audit passed |
| Developer ID signing | pass; all 26 Mach-O files use hardened runtime, valid strict signatures, matching Team IDs, and only `beam.smp` has the JIT entitlement |
| Apple notarization and Gatekeeper | pass; final submission `ec1ecdef-220e-418b-a4f3-29557d53721b` accepted with zero issues, ticket stapled and validated, Gatekeeper reports `Notarized Developer ID` |
| Extracted quarantined ZIP | pass; stapler and Gatekeeper accepted it and all 22 sterile runtime checks passed |
| Separate clean macOS account | pass on repeat; all 22 checks passed as UID 502 with a separate home and sterile `PATH`; the first cold run passed 20 checks but its synthetic pre-readiness failure exceeded the 8-second harness bound before cleanup |
| Native dependency audit | pass; 26 Mach-O files and no non-system absolute load dependency after excluding dylib identity records |
| Shellcheck | unavailable on the host; shell syntax checks passed |

`rtk proxy` was used where exact build, signing, notarization, or subprocess
output is operationally required. GitHub Actions has one unavoidable bootstrap
command to install RTK; every subsequent workflow shell command uses RTK.

## Handoff

Task complete after final review and local-main merge. The ignored release
artifact is `desktop/dist/Cuckoding-0.1.0-macos-arm64.zip` with SHA-256
`a7d80cd5961be643215505a9a90db3d91987d50cee64ab4d298c8bb439081faf`.
The clean-account evidence is from the supported host rather than a second
physical Mac. Task 0903 owns updates, backups, migrations, and rollback.
