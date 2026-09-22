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
under a sterile environment. Use `rtk ./bin/dev.build` as the developer-facing
entrypoint. That local artifact is not signed or notarized.

## Release commands

`desktop/release.sh` is the single Apple Silicon release entrypoint. It requires
a clean worktree and `CUCKODING_SIGNING_IDENTITY`, builds the embedded release,
discovers and signs every Mach-O in the app, submits a temporary ZIP to Apple's
notary service, staples and validates the ticket, asks Gatekeeper to assess the
app, then emits the final ZIP, signed `.app.tar.gz` updater bundle,
`latest.json`, CycloneDX SBOM, provenance, checksums, and the complete
notarization response and log under ignored `desktop/dist/`.
The release is assembled in an ignored candidate directory; `desktop/dist/`
is replaced only after notarization, updater signing, and metadata generation
all succeed. If candidate preparation fails, it remains in
`desktop/src-tauri/target/release/` for inspection and the previous `dist/`
stays unchanged. A successful
replacement keeps the prior distribution in a private
`desktop/dist-backup.*` directory outside Cargo's build outputs. Do not delete that
backup until the new artifacts have been installed and checked. Promotion
rejects incomplete candidates and symlink destinations.

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
`TAURI_SIGNING_PRIVATE_KEY_PATH`, plus a nonempty
`TAURI_SIGNING_PRIVATE_KEY_PASSWORD`. Only the public key is embedded in the app.
`desktop/release.sh` immediately removes the private key and password from the
inherited build environment and exposes them only to the signer process; an
inline CI secret is copied to a private temporary file and removed on exit.

### CI credential handoff

The local `Cuckoding` `notarytool` Keychain profile uses this Mac's Apple ID
app-specific password. GitHub's hosted runner cannot use that profile: the
current workflow requires an export of the **Developer ID Application identity
and its private key**, plus a separate **App Store Connect Team API key**.
Moving those credentials into GitHub Actions is a stakeholder security decision;
do not send them in chat, commit them, or print them in logs. If that transfer
is not approved, use the local release path with the existing Keychain profile
and an authorized updater private key instead; do not bypass signing checks.

1. In Keychain Access → **My Certificates**, select the Developer ID Application
   identity used by the successful local signing drill, confirm it includes a
   private key, and export a password-protected `.p12` outside this repository.
   A downloaded `.cer` alone is not a signing identity. Set the repository
   Actions secret `APPLE_CERTIFICATE` to the `.p12` bytes encoded as base64 and
   `APPLE_CERTIFICATE_PASSWORD` to its export password. Verify the existing
   `APPLE_SIGNING_IDENTITY` names that same identity. See [Apple's Keychain
   export guide](https://support.apple.com/guide/keychain-access/kyca35961/mac)
   and [GitHub's binary-secret guidance](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets#storing-base64-binary-blobs-as-secrets).
2. In App Store Connect → **Users and Access** → **Integrations** → **Team
   Keys**, create a key permitted to use notarization and securely retain its
   one-time-downloaded `.p8`. Set `APPLE_NOTARY_KEY` to the `.p8` contents,
   `APPLE_NOTARY_KEY_ID` to that key's ID, and `APPLE_NOTARY_ISSUER` to its
   App Store Connect issuer UUID. The Apple Developer **Team ID is not the
   issuer ID**. This workflow supplies `--issuer`, so it requires a Team key;
   Apple says Individual keys cannot use `notarytool`. See [Apple's Team-key
   instructions](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)
   and [API-key rules](https://developer.apple.com/documentation/AppStoreConnectAPI/creating-api-keys-for-app-store-connect-api).
3. Add the five values under this repository's **Settings → Secrets and
   variables → Actions → Repository secrets**. Review who can edit or run the
   release workflow. Then rerun `release-macos` manually on `main`; manual runs
   do not publish a GitHub Release. Check its signed/notarized artifact and
   evidence before creating a `v*` tag. Retain a secure backup of the exported
   identity and key before removing temporary export files. See [GitHub's
   repository-secret instructions](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets#creating-secrets-for-a-repository).

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
Before importing the certificate or exposing any notary/updater signing secret,
the release job fetches pinned Mix dependencies and runs `mix quality` (format,
warnings-as-errors compile, tests, strict Credo, Sobelow, dependency audit).
A failed source gate stops packaging and publication. The next step checks all
required secret and update-variable names for nonempty values and reports only
missing names; it does not print values or attempt signing. A missing item
stops the job before certificate import. The first manual CI run on `131e171`
found two Claude adapter tests that assumed an installed CLI; after those
fixtures were corrected, [run 35663188771](https://github.com/mpakus/cuckoding.com/actions/runs/35663188771)
on `112473e` passed `mix quality` (288 tests, 10 properties) and stopped at
the preflight because `APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`,
`APPLE_NOTARY_KEY`, `APPLE_NOTARY_KEY_ID`, and `APPLE_NOTARY_ISSUER` were
missing. This verifies the fail-closed ordering, not signing or release.
GitHub Actions'
[`macos-15` image](https://github.com/actions/runner-images#available-images)
is Apple Silicon, matching the release script's host check.
All five workflow action refs (four build-job, one publish-job) were checked
against upstream commit APIs on 2026-09-21. Two earlier non-resolving refs for `erlef/setup-beam` and
`apple-actions/import-codesign-certs` were replaced with verified pinned
commits matching v1.24.1 and v7.0.0 respectively. Pin validity is not a
substitute for an executed macOS job.

The production update host is GitHub Releases. Both update URL variables use
GitHub's `latest/download` redirect: the endpoint ends in `latest.json`, while
the base URL is the same path without that filename. A `v*` tag runs the
verified build in a read-only job, then a separate job with only
`contents: write` downloads that exact Actions artifact and publishes all
release, updater, checksum, provenance, SBOM, and notarization evidence assets.
Manual workflow runs retain the Actions artifact but do not publish a release.
The updater private key and its password remain secrets; only the public key is
a repository variable and embedded in the application.

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

A later local drill signed the developer app built from `3246b3b` with the
current Developer ID, verified all 26 Mach-O files, and notarized it using the
saved Keychain profile. Apple accepted submission
`02d108c6-87f9-4b31-b515-28444fa98938` with zero issues; the ticket was
stapled, Gatekeeper accepted the app, and the embedded release passed the
sterile verifier after signing. This did not run `desktop/release.sh` or
replace `desktop/dist/`: the updater archive/signature, complete release
metadata, GitHub Actions job, and clean-Mac install still need current-revision
acceptance.

The same local app was subsequently archived **after** stapling as
`Cuckoding-0.1.0-macos-arm64-stapled.zip` in the ignored local candidate
directory. Its SHA-256 is
`171529c3d4ee18970b04f0f6fc66fe9ccea2a8158ba4c270b645af220eadcd3c`.
The ZIP passed `unzip -tq`; a separately extracted copy with a quarantine
attribute passed `stapler validate`, strict deep `codesign --verify`, and
Gatekeeper with `source=Notarized Developer ID`. Its embedded release passed
the sterile startup, authentication, crash, safe-mode, and update/rollback
checks. This is a **same-Mac archive smoke**, not an installed clean-Mac test
or the complete `desktop/release.sh` output. The older `desktop/dist/` and its
updater metadata were not replaced; do not publish this standalone ZIP as an
accepted enrollment release.

On 2026-09-21 a separate isolated checkout of then-current `17d367a` built
a fresh unsigned app and passed the sterile release verifier. The local
Developer ID signed all 26 Mach-O files; Apple accepted notarization submission
`4d7775e9-32da-4815-b4d9-e624a7fb27d6` with no issues, and stapling and
Gatekeeper assessment passed. A ZIP made **after** stapling has SHA-256
`bcfa5afccc7740a4dbb9ba9178a8032ae58889172b97d3467612967c1d983a07`.
Its quarantined, separately extracted app passed ticket validation, strict
signature verification, Gatekeeper, and the embedded-release sterile verifier
again. The ignored local candidate remains under
`/Users/mpak/.codex/worktrees/phase10-current-build/cuckoding.com/desktop/src-tauri/target/release/Cuckoding-local-notary.CrJSDY/`;
the checksum-matched copy at
`/Users/Shared/Cuckoding-0.1.0-17d367a-stapled.zip` is readable by the
existing `qa` account. `desktop/dist/` and the staged older QA ZIP were not
replaced. This is
same-Mac revision-specific app evidence, not an updater signature, complete
release package, separate-account launch, or clean-Mac acceptance.

Newer `a3ef7b1` source passed the complete `bin/dev.build` developer build on
2026-09-21, including the embedded release's sterile verifier. The local
Developer ID signed all 26 Mach-O files; Apple accepted notarization
submission `9bcbd65e-79f4-43a2-b324-3f49be5c5b1e` with zero issues.
The ticket was stapled, Gatekeeper accepted the app, and its embedded release
passed the sterile verifier after signing. A ZIP made **after** stapling has
SHA-256
`242857407ea002472a1f767203d498a85c595d2e7a7fdaa58566704e7f1bd1f5`.
A quarantined, separately extracted copy passed ticket, strict-signature,
Gatekeeper, and embedded-release sterile checks on the same Mac. The ignored
candidate and evidence remain under
`desktop/src-tauri/target/release/Cuckoding-local-notary-a3ef7b1.aJWS9F/`;
the checksum-matched copy at
`/Users/Shared/Cuckoding-0.1.0-a3ef7b1-stapled.zip` is readable by the
existing `qa` account. A first Tauri bundle attempt returned `Operation not
permitted`, but a direct rerun and the complete build passed; the isolated
failure's cause is unconfirmed. This is not a signed updater, complete
release package, separate-account launch, or clean-Mac acceptance.

After the process-inspection fix, `6ebbd6c` source passed `bin/dev.build`,
including production compilation, Rust checks, and the sterile bundled-release
verifier. The local Developer ID signed all 26 Mach-O files; Apple accepted
notarization submission `bf94f6da-a3c4-4bf0-a512-4408599973bc` with zero
issues. The stapled app and a separately extracted, quarantined copy of its
post-staple ZIP passed ticket validation, strict signature verification,
Gatekeeper (`Notarized Developer ID`), and the sterile embedded-release drill.
The ZIP SHA-256 is
`c5f17966f69123c490fb7e048d0476ae5937ed2177d7b936ee653e3787783d1e`.
The ignored candidate and notarization evidence remain under
`desktop/src-tauri/target/release/Cuckoding-local-notary-6ebbd6c.waSlcF/`;
the checksum-matched, readable QA copy is
`/Users/Shared/Cuckoding-0.1.0-6ebbd6c-stapled.zip`. Older candidates and
`desktop/dist/` were not replaced. This remains a same-Mac app check, not an
updater, complete release package, separate-account launch, or clean-Mac test.

Current app code `d7a6222` passed `bin/dev.build`, including the sterile
embedded-release verifier. The local Developer ID signed all 26 Mach-O files;
Apple accepted notarization submission
`ed83bd11-eea6-47a8-a530-5c9dfdb2ef77` with zero issues. The stapled app
and a separately extracted, quarantined copy of its post-staple ZIP passed
ticket validation, strict signature verification, Gatekeeper (`Notarized
Developer ID`), and the sterile embedded-release drill. The ZIP SHA-256 is
`02cf32e4b2d0f39ea3a769f3f86f8bb8f06706a0d985ccad58c64eadb489f329`.
The ignored candidate and notarization evidence remain under
`desktop/src-tauri/target/release/Cuckoding-local-notary-d7a6222.ONaa7d/`;
the checksum-matched, readable QA copy is
`/Users/Shared/Cuckoding-0.1.0-d7a6222-stapled.zip`. Earlier candidates and
`desktop/dist/` were not replaced. This is a same-Mac app check, not an
updater, complete release package, separate-account launch, or clean-Mac test.

For a separate-account smoke, use the **latest `d7a6222` ZIP** staged above.
The older `6ebbd6c`, `a3ef7b1`, `17d367a`, and `3246b3b` ZIPs remain staged
only as historical evidence. Sign into the existing `qa` macOS account, extract the `d7a6222`
copy into that account's own folder, launch it from Finder, check the
menubar-to-browser handoff and clean quit, then inspect the
QA account's application data. Do not sign agents in or register a real
project for this shell-only check. Cuckoding's shell uses the account-derived
`app_data_dir()` with no reviewed test override, so launching it as the
current user could touch the live application database. The QA login has not
yet been performed; this local handoff is neither a downloaded-file test nor
a clean physical Mac or updater acceptance result.

## Tool discovery

macOS GUI applications do not inherit an interactive shell's dotfile `PATH`. Search configured paths and known safe locations (Homebrew, `~/.local/bin`, npm global, cargo), allow the user to select an executable, and store verified paths. Display version and health for Git, each agent runtime, and each plugin binary.

## Data locations and backup

The native shell's application data is under
`~/Library/Application Support/com.cuckoding.desktop/`: SQLite, artifacts,
logs, plugins, global knowledge, and the default workspace root. Before updates
and migrations, make a versioned database backup and a knowledge snapshot and
record active run identifiers. Offer export of configuration, audit, and
knowledge artifacts. Direct replacement of an unsigned developer bundle uses
the separately documented backup-first maintenance path in `DEVELOPMENT.md`;
it must not forge signed-updater state.

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
  reconciliation, power, or sampling workers. Diagnostics export remains
  available for recovery evidence.

## Diagnostics bundle

The settings page discloses the fixed bundle contents and exclusions before an
explicit export. The generated owner-only ZIP is stored under the application
data diagnostics directory and contains exactly seven bounded JSON files:
manifest, allowlisted runtime/project configuration, migration status, plugin
identity and health, power-event summaries, normalized recent error IDs, and
aggregate process states.

The bundle never includes repository or worktree contents, prompts, provider
output, credentials, raw logs or command output, argv, environment variables,
plugin manifests or free-form errors, or absolute repository, manifest,
artifact, and knowledge paths. Every member passes through the shared redactor,
the total uncompressed input is capped at 2 MiB, row sets are bounded, and
symlinked output locations are rejected. The same export works in safe mode.

## Future targets

Linux: the same release with a tray icon shell (or none, headless `cuckoding serve` packaged with Burrito) and container runner plugins where Docker is native. Windows: later. A remote runner uses the same `RunnerBridge` semantics with mutual authentication, transport security, artifact transfer, and remote secret boundaries.
