# BOSS 0.1.0-rc.1

Status: local macOS release candidate verified on the build host. No public release, tag,
signature/notarization or remote CI result is implied by this document. Results
and remaining gates are recorded in [.worklog/2026-10-29.md](../.worklog/2026-10-29.md).

[Draft RC PR #1](https://github.com/mpakus/cuckoding.com/pull/1) publishes the reviewed
source on a separate branch; remote main and the existing site are preserved.
Remote CI is in progress. Its PR merge checkout is distinct from the branch head
and must be matched to the final artifact's `BUILD_INFO` before claiming acceptance.

Local application regression passed585 tests with1 platform-specific skip
(seed329391). The unpacked archive passed native-helper execution, private browser
authentication/assets, connected LiveView board/Autopilot/drawer and durable restart.
Public distribution still requires the open gates below.

One explicitly authorized real Codex0.146.0 packaged workflow passed in100.875s
with3 CLI invocations: plan, implement, checks, independent Codex review, exact
publication and postchecks reached Done. Review passed5/5 criteria with0 issues;
all process receipts confirmed exit0, both EOFs and group cleanup. Independent
target inspection found only the exact `hello.txt` addition and preserved the
original `user-work` checkout. This tiny smoke covers the selected Codex reviewer;
it does not establish arbitrary task, Claude-provider or clean-machine acceptance.
Sanitized [receipts and usage](../.worklog/evidence/2026-10-29-codex-rc-smoke.json)
exclude model/tool text and report prose. No second paid workflow was started.

BOSS uses Apache-2.0, selected by the project owner. The archive
includes the unchanged project license as `LICENSES/BOSS-LICENSE`; dependency
notices retain their original licenses.

## Build and inspect

Use the pinned Elixir1.20.3/OTP28 pair, Node20+ with npm, Git, Python3.12+ and Xcode
Command Line Tools on macOS. Runtime dependencies must be built on the intended
OS/architecture; this is not a universal or cross-compiled archive.

```sh
mix setup
mix hex.audit
npm --prefix assets audit --audit-level=high
mix format --check-formatted
mix compile --warnings-as-errors
mix test
MIX_ENV=prod mix release.build
python3 scripts/smoke_release.py _build/prod/boss-0.1.0-rc.1.tar.gz
shasum -a 256 _build/prod/boss-0.1.0-rc.1.tar.gz
```

On this development machine run Mix through `rtk proxy asdf exec mix`. Use RTK
for other terminal commands as described in AGENTS.md.

Inspect the archive's `BUILD_INFO` and `LICENSES` before distribution. The package
contains ERTS, Elixir/application code, native guardian, compiled assets, migrations
and bundled non-system native libraries. Its recorded source SHA/dirty flag,
OS/architecture and runtime versions describe that artifact, not another build.
Never label an archive built from a dirty tree as the verified tagged source.
The current development host is macOS27.0.1 arm64; its native minimum-OS headers
do not establish compatibility with older macOS versions. CI-built archives have
their own provenance and require acceptance on their intended machines.

The included OpenSSL library is relocated into the release; assembly rejects
remaining external non-system native-library dependencies. Ad-hoc signatures used
after relocation support local loading. They do not provide Developer ID trust or
Apple notarization.

Inspection of the local macOS27 archive found26 arm64 native images: guardian
requires macOS27.0,24 images require26.0 and Exqlite requires14.0. This archive
therefore requires macOS27.0 or later; a different CI build needs its own inspection.

## Explicit macOS distribution preparation

The optional signing step requires a maintainer-approved Developer ID Application
identity and private-key access. Inspect available public identity metadata with
`security find-identity -v -p codesigning`; select the exact40-character certificate
fingerprint, rather than automatically using the first identity. Signing uses
Apple's secure timestamp service. From a reviewed clean source checkout:

```sh
python3 scripts/sign_macos_release.py /absolute/boss-0.1.0-rc.1.tar.gz \
  --identity CERTIFICATE_SHA1 --output /absolute/new-boss-distribution
```

The output directory must not already exist. The step preserves the input archive,
signs each native file with hardened runtime and the same Developer ID Team, grants
only `com.apple.security.cs.allow-jit` to `beam.smp`, verifies the signatures and
runs the existing unpacked smoke on the signed payload. It then creates and signs
a read-only UDZO `boss.dmg` containing a copyable `boss/` folder. The completed
output includes `SIGNING_INFO.json` and `SHA256SUMS`. The original `BUILD_INFO`
describes assembly; `SIGNING_INFO.json` records the subsequent signing step.
Failure may leave a partial output directory; preserve it for diagnosis and use
a different fresh destination after correcting the cause.

This step does not submit anything for notarization. Its fixture tests verify
command selection and failure handling; real Developer ID smoke remains a separate
acceptance gate. An ad-hoc hardened-runtime experiment failed macOS library
validation while loading crypto: ad-hoc images have no common signing Team.
That failure does not justify disabling library validation or widening entitlements.
The unmodified local archive's earlier successful smoke is separate evidence.

After explicit upload authorization and Keychain-profile setup, submit the signed
DMG once using the approved profile. No passwords, API keys or credential files
belong in this repository, command history or logs:

```sh
xcrun notarytool submit /absolute/new-boss-distribution/boss.dmg \
  --keychain-profile APPROVED_PROFILE --wait --timeout 20m --output-format json
```

Retain the submission ID and require final `Accepted` status. Timeout or lost
output does not prove rejection or cancellation: reconcile the same submission
through `notarytool info`/`wait` (or account history if its ID was lost), rather than
submitting again. An `Invalid` result requires diagnosis from that submission's
log and a new explicitly reviewed artifact. After acceptance:

```sh
xcrun stapler staple /absolute/new-boss-distribution/boss.dmg
xcrun stapler validate /absolute/new-boss-distribution/boss.dmg
spctl -a -vv -t open --context context:primary-signature /absolute/new-boss-distribution/boss.dmg
```

Stapling changes the delivered bytes: regenerate and verify `SHA256SUMS` afterward.
Keep notarization/submission evidence separate from the pre-upload signing record.
Test the actual quarantined download on a supported clean Mac, copy `boss/` out of
the mounted image and follow the launch instructions below, including native
folder selection and an authorized provider workflow. Local signatures or an
online Gatekeeper lookup alone do not prove a stapled offline delivery works.
Do not remove quarantine or disable Gatekeeper to pass this gate.

## Install and run locally

Extract into a new application folder; keep the archive/checksum and avoid
overwriting a running version. From the extracted directory:

```sh
bin/boss start
```

The launcher works from another current directory when invoked by its full path.
Open `http://127.0.0.1:4000` and enter the one-use terminal token. Never put the token
in a URL or persistent log. Keep the terminal open; use Ctrl-C or send TERM to the
foreground process to stop. Distribution is disabled, so `rpc`, `remote` and the
distribution-based `bin/boss stop` command are not the shutdown interface.
The release disables BEAM crash-dump files because they can include private
in-memory agent output; this setting does not control host OS core-dump policy.

Git and the selected Codex/Claude CLI must be installed, authenticated and available
on the launching terminal's PATH. A desktop session is required for native folder
dialogs. Agent accounts can incur charges. Elixir, Node and a C compiler belong to
the build setup; an accepted bundled archive should not need them at runtime.
The public signing/notarization gate must be completed before promising a normal
download-and-open experience; do not disable Gatekeeper to pass acceptance.

For an isolated first launch use a fresh data directory and unused port:

```sh
BOSS_DATA_DIR=/absolute/private/boss-rc-data PORT=4010 /absolute/boss/bin/boss start
```

Use a real new private directory, not production data, for smoke acceptance.
The reusable smoke checks only local fixtures; provider acceptance stays opt-in.

## Update and recover data

1. Pause scheduling, stop active work and confirm known cleanup. Unknown outcomes
   require the existing recovery investigation; restarting does not clear them.
2. Stop BOSS before making a consistent backup. Preserve the entire private data
   directory (default `~/.boss`), including retained worktrees, together with each
   registered repository and its Git common directory/refs at the same point.
   Use a filesystem snapshot or private backup that preserves permissions and paths.
3. Extract the new version into a separate folder. Start it against the intended
   data directory; startup obtains the ownership lock and migrates before HTTP starts.
4. Verify unlock, saved projects/specs/tasks, retained evidence and native chooser.
   Start a harmless task only when its actual provider call is authorized.

Do not delete the ownership lock or run `mix ecto.*` against a running instance.
Do not downgrade only the executable after a schema upgrade. If rollback is needed,
stop BOSS and restore a matching complete data/repository snapshot with the matching
previous binary. Preserve the failed version and newer history for diagnosis; a
restore must not silently discard work created after the backup.

## Publication gates

| Gate | Required evidence |
|---|---|
| Full regression | All application tests pass on the final source/dependency tree; no hidden fixture failures. |
| Package | Actual unpacked startup, unlock/assets, native helper and durable restart with bundled runtime; checksum and provenance. |
| Dependency audit | Hex and npm audit pass without suppressing findings. |
| Clean-machine macOS | Supported architecture/OS acceptance with user-installed Git and CLI; actual folder chooser and provider workflow. |
| Provider | Passed one bounded packaged Codex workflow with Codex review through checks/integration/Done (3calls/100.875s). Other providers and arbitrary tasks need separate evidence. |
| Distribution | Apache-2.0 selected and included; public signing/notarization and download acceptance remain open. Third-party notices retain their original licenses. |
| Remote CI | Pinned macOS workflow runs successfully on the published commit; local YAML validation is not a remote result. |
| Linux stable support | Linux process ownership/cleanup, native chooser and complete workflow acceptance. Current runner rejects non-macOS execution. |

The [candidate workflow](../.github/workflows/release-candidate.yml) tests, audits,
assembles and smoke-checks a host-specific artifact with a checksum. It has read-only
repository permissions and does not create a GitHub Release or change Latest.
Stable and prerelease artifacts must remain distinct; the local RC is not a stable
release. Existing recovery limits remain in [RECOVERY.md](RECOVERY.md).

Implementation references: [Mix release](https://mix.hexdocs.pm/Mix.Tasks.Release.html),
[setup-beam](https://github.com/erlef/setup-beam),
[Bandit fixed-version advisory](https://github.com/mtrudel/bandit/security/advisories/GHSA-cpx7-qf6w-jc63).
Signing references: [Apple distribution packaging](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution/),
[Apple silicon JIT](https://developer.apple.com/documentation/apple-silicon/porting-just-in-time-compilers-to-apple-silicon).
