# Distribution and Operations

## Initial target

The first supported artifact is a macOS Apple Silicon `.app` built from the menubar shell (`docs/DESKTOP_SHELL.md`) with the Phoenix release, ERTS, assets, bundled plugins, and required native libraries inside `Contents/Resources`. Git, agent runtimes, and plugin binaries are discovered on the machine; the UI makes bundled versus discovered explicit.

## Build pipeline

1. Build and test Phoenix assets and the production release for the target.
2. Verify native library paths and release startup without system Erlang/Elixir and without an interactive shell `PATH`.
3. Build the shell and embed the release directory as a resource.
4. Generate an SBOM and dependency/license inventory.
5. Sign every Mach-O in the bundle (including ERTS executables and NIFs) with hardened runtime and the JIT entitlement the BEAM needs on Apple Silicon; notarize the app and updater artifacts.
6. Publish checksums, provenance, update manifest, and release notes.
7. Install and smoke-test on a clean supported machine.

## Startup contract

See the shell contract in `docs/DESKTOP_SHELL.md`. The production Tauri project
is `desktop/`; its local build embeds the release and runs `desktop/verify.rb`
under a sterile environment. That local artifact is not signed or notarized.

## Release commands

`desktop/release.sh` is the single Apple Silicon release entrypoint. It requires
a clean worktree and `CUCKODING_SIGNING_IDENTITY`, builds the embedded release,
discovers and signs every Mach-O in the app, submits a temporary ZIP to Apple's
notary service, staples and validates the ticket, asks Gatekeeper to assess the
app, then emits the final ZIP, signed `.app.tar.gz` updater bundle,
`latest.json`, CycloneDX SBOM, provenance, checksums, and the complete
notarization response and log under ignored `desktop/dist/`.

For a developer workstation, set `CUCKODING_NOTARY_PROFILE` to a profile
created with `xcrun notarytool store-credentials`; do not put the credential in
the repository or command history. CI instead uses an App Store Connect private
key file plus its key ID and issuer ID. The private key and Developer ID
certificate are repository secrets, written only to the ephemeral runner.

Tauri update signing is independent of Apple code signing. Generate that
keypair outside the repository with `rtk proxy cargo tauri signer generate
--write-keys /private/path/cuckoding-updater.key`, protect the private key with
mode `0600`, and keep its password in the release secret store. Release builds
require `CUCKODING_UPDATE_ENDPOINT` (the HTTPS `latest.json` URL),
`CUCKODING_UPDATE_BASE_URL` (the HTTPS artifact directory),
`CUCKODING_UPDATER_PUBLIC_KEY`, and either `TAURI_SIGNING_PRIVATE_KEY` or
`TAURI_SIGNING_PRIVATE_KEY_PATH`. Only the public key is embedded in the app.
`desktop/release.sh` immediately removes the private key and password from the
inherited build environment and exposes them only to the signer process; an
inline CI secret is copied to a private temporary file and removed on exit.

The pinned `.github/workflows/release-macos.yml` workflow expects these GitHub
Actions secrets: `APPLE_CERTIFICATE` (base64 PKCS#12),
`APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_NOTARY_KEY`
(the `.p8` contents), `APPLE_NOTARY_KEY_ID`, and `APPLE_NOTARY_ISSUER`. It has
read-only repository permissions, removes the temporary private-key file even
after failure, and uploads artifacts only after signing, notarization, stapling,
Gatekeeper assessment, updater signing, SBOM generation, and checksum
generation all succeed. It additionally requires the
`TAURI_SIGNING_PRIVATE_KEY` and `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` secrets,
plus `CUCKODING_UPDATE_ENDPOINT`, `CUCKODING_UPDATE_BASE_URL`, and
`CUCKODING_UPDATER_PUBLIC_KEY` repository variables.

`desktop/sign.sh` may be run independently to exercise local Developer ID
signing before notarization. Only `beam.smp` receives
`com.apple.security.cs.allow-jit`; every other Mach-O uses hardened runtime with
no exception entitlement. Successful local signing is not notarization and is
not clean-Mac acceptance evidence.

The release build discovers OTP crypto's linked `libcrypto`, copies it beside
the OTP NIFs, rewrites their load commands to `@loader_path`, and fails if any
non-system absolute library dependency remains. The final SBOM includes that
bundled OpenSSL binary and its post-signing SHA-256 digest.

Task 0902 release evidence is complete for the Apple Silicon host: Apple
accepted submission `ec1ecdef-220e-418b-a4f3-29557d53721b` with zero issues;
the ticket was stapled and validated; Gatekeeper accepted the quarantined,
freshly extracted ZIP; and all 22 sterile runtime checks passed under the
separate `qa` macOS account. This verifies a clean account on the supported
host, not a second physical Mac.

## Tool discovery

macOS GUI applications do not inherit an interactive shell's dotfile `PATH`. Search configured paths and known safe locations (Homebrew, `~/.local/bin`, npm global, cargo), allow the user to select an executable, and store verified paths. Display version and health for Git, each agent runtime, and each plugin binary.

## Data locations and backup

Application data in `~/Library/Application Support/Cuckoding/`: SQLite, artifacts, logs, plugins, global knowledge, and the default workspace root. Before updates and migrations, make a versioned database backup and a knowledge snapshot and record active run identifiers. Offer export of configuration, audit, and knowledge artifacts.

## Updates

- Tauri checks the pinned HTTPS manifest and verifies the detached signature
  before the update boundary receives bytes.
- The manifest carries release notes and an explicit `schema_change` flag;
  unknown impact defaults to schema-changing.
- Phoenix hibernates active runs and rechecks that none remain before creating
  the database, knowledge, and configuration snapshot.
- The candidate runs forward migrations with logged pending/completed counts.
  Unknown applied migrations abort startup instead of downgrading onto an
  incompatible database.
- Health promotion removes the pending marker and previous app only after
  READY and authenticated shell startup succeed. Failure restores the snapshot
  and app while retaining the failed database in the backup directory.
- Safe mode exposes authenticated history without starting runner, plugin,
  reconciliation, power, or sampling workers. The diagnostics export arrives
  with Task 0904.

## Diagnostics bundle

Generate a user-reviewed, redacted archive containing versions, configuration schemas and hashes, health checks, plugin states, power events, recent normalized errors, migration status, process summaries, and selected event IDs. Exclude source contents, raw prompts, credentials, and full environment variables by default.

## Future targets

Linux: the same release with a tray icon shell (or none, headless `cuckoding serve` packaged with Burrito) and container runner plugins where Docker is native. Windows: later. A remote runner uses the same `RunnerBridge` semantics with mutual authentication, transport security, artifact transfer, and remote secret boundaries.
