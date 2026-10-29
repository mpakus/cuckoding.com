# BOSS 0.1.0-rc.1

Earlier source a0b9715 passed full remote regression (587 passed,1 skipped).
The corrected runtime/local archives passed build, native/notice review and actual
smoke. Latest full CI at34053fd failed two cases (589 passed,2 failed,1 skipped):
an implicit100ms queue receipt wait and unknown cleanup after output_limit.
Reviewed corrections add bounded fixture waits and retire controls after terminal
receipt while requiring helper exit0. Combined acceptance passed198 tests and200
raw native stress runs. A new macOS14 early-native/full pipeline remains pending;
original CI message ordering is not established retrospectively.
Earlier Developer ID signed5570d3f is held from distribution: its OpenSSL3.6.3
predates published upstream fixes. Valid signatures do not close this gate.
No public release, tag or notarization is implied. Results and remaining gates are
in [.worklog/2026-10-29.md](../.worklog/2026-10-29.md).

[Draft RC PR #1](https://github.com/mpakus/cuckoding.com/pull/1) publishes the reviewed
source on a separate branch; remote main and the existing site are preserved.
[CI40953808199](https://github.com/mpakus/cuckoding.com/actions/runs/40953808199)
passed all587 tests (1 skipped), audits and signing fixtures. Packaging then
rejected the prebuilt runtime: its crypto NIF statically embeds OpenSSL3.5.6,
and the binary distribution lacks upstream notices. No CI archive was produced.
The actual tested merge is a9af06bf077e9bec967558db3df63e9cfbff9638; its tree equals
PR head a0b9715. A replacement isolated source build targets OTP28.5.0.8 with
OpenSSL3.5.9 LTS; build/package acceptance remains pending. See
[OpenSSL releases](https://www.openssl-library.org/source/) and
[advisory ranges](https://www.openssl-library.org/news/vulnerabilities-3.6/index.html).
These library findings do not establish a remotely exploitable BOSS issue.
The subsequent [patched-runtime CI40963324835](https://github.com/mpakus/cuckoding.com/actions/runs/40963324835)
passed runtime/build/audits and focused package/signing checks, then failed the two
application cases above. No remote artifact was produced. Local2e packaging proof
remains valid; that archive is held from distribution pending combined acceptance.
PR head, tested merge SHA and final artifact `BUILD_INFO` remain separate facts.

Historical baseline regression passed585 tests with1 platform-specific skip
(seed329391,018a). Original archive9596162 passed native-helper execution, private
browser authentication/assets, connected board/Autopilot/drawer and durable restart.
The new Git-runtime fix passed49 related cases and640 concurrent adds; combined
workspace/dependency verification passed32. The rebuilt5570 package passed unsigned
and signed-payload smoke, but its native crypto now blocks distribution. Public
distribution requires a corrected package and the remaining gates below.

One explicitly authorized real Codex0.146.0 packaged workflow passed in100.875s
with3 CLI invocations: plan, implement, checks, independent Codex review, exact
publication and postchecks reached Done. Review passed5/5 criteria with0 issues;
all process receipts confirmed exit0, both EOFs and group cleanup. Independent
target inspection found only the exact `hello.txt` addition and preserved the
original `user-work` checkout. This tiny smoke covers the selected Codex reviewer;
it does not establish arbitrary task, Claude-provider or clean-machine acceptance.
Sanitized [receipts and usage](../.worklog/evidence/2026-10-29-codex-rc-smoke.json)
exclude model/tool text and report prose. They pin archive build9596162 and
SHA256a958c8d8ee81b22eb77413f0dc01defd34db3fc67c08a32ce119753e15bff57f.
Fresh provider acceptance of the subsequent Git-registration runtime change remains
a separate opt-in gate. No second paid workflow was started.

BOSS uses Apache-2.0, selected by the project owner. The archive
includes the unchanged project license as `LICENSES/BOSS-LICENSE`; dependency
notices retain their original licenses.

## Build and inspect

Release builds require native macOS arm64, Python3.12+, Xcode Command Line Tools,
Git, Node20+ with npm and Elixir1.20.3 compiled for OTP28. Build the pinned
OTP28.5.0.8/OpenSSL3.5.9 runtime in an exclusively new prefix; this does not change
Homebrew or asdf installations. Existing output directories are refused and failed
outputs are retained with their build logs. Choose a new output name for another
build. Runtime dependencies must be built on the intended OS/architecture.

```sh
rtk proxy python3 -B scripts/test_build_release_runtime.py
rtk proxy python3 -B scripts/build_release_runtime.py --output "$PWD/_build/release-runtime" --jobs 3
export PATH="$PWD/_build/release-runtime/otp/bin:$PATH"
rtk proxy elixir --version
rtk proxy elixir rel/test_package.exs
rtk proxy mix setup
rtk proxy mix hex.audit
rtk proxy npm --prefix assets audit --audit-level=high
rtk proxy mix format --check-formatted
rtk proxy mix format --check-formatted rel/package.exs rel/test_package.exs
rtk proxy mix compile --warnings-as-errors
rtk proxy mix test
rtk proxy env MIX_ENV=prod mix release.build
rtk proxy python3 -B scripts/smoke_release.py _build/prod/boss-0.1.0-rc.1.tar.gz
rtk proxy shasum -a 256 _build/prod/boss-0.1.0-rc.1.tar.gz
```

The selected Elixir must be1.20.3-otp-28; put that installation's `bin` after the
new OTP `bin` if PATH chooses another Elixir. On this host that is
`/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin`. The effective `erl` must stay
inside the new prefix for every build/test command; do not silently revert to the
Homebrew/asdf default Erlang. The packaging gate verifies the actual runtime,
exact crypto NIF bytes and source manifest. CI applies the same prefix before
installing dependencies and running the complete suite.

Inspect the archive's `BUILD_INFO` and `LICENSES` before distribution. The package
contains ERTS, Elixir/application code, native guardian, compiled assets, migrations
and bundled non-system native libraries. Its recorded source SHA/dirty flag,
OS/architecture and runtime versions describe that artifact, not another build.
Never label an archive built from a dirty tree as the verified tagged source.
The current development host is macOS27.0.1 arm64; its native minimum-OS headers
do not establish compatibility with older macOS versions. CI-built archives have
their own provenance and require acceptance on their intended machines.

This RC accepts only the pinned source-built static OpenSSL runtime. Assembly
rejects stale/unsupported versions, a changed crypto NIF, missing notices and
external non-system native dependencies, including hidden images and escaping
loader paths. `RUNTIME_INFO.json` records source/archive hashes, configure options,
actual versions and genuine notice hashes; `BUILD_INFO` pins that manifest.
OTP's separate builtin MD5-only OpenSSL3.6.1 source component is recorded distinctly
from the effective full OpenSSL3.5.9 crypto library. System zlib is provided by
macOS. Build signatures do not provide Developer ID trust or Apple notarization.

Historical5570 archive inspection found26 arm64 native images: guardian
requires macOS27.0,24 images require26.0 and Exqlite requires14.0. This archive
therefore requires macOS27.0 or later; a different CI build needs its own inspection.

## Explicit macOS distribution preparation

Historical local candidate5570d3f has independent strict verification of its DMG and all26
arm64 native images under the selected Developer ID TeamG4HV2FL5N2, with secure
timestamps, hardened runtime and only BEAM allow-jit. The signed payload passed
unpacked startup/auth/assets/native-helper/restart smoke. See sanitized
[signing evidence](../.worklog/evidence/2026-10-29-signed-macos-rc.json).
This is historical signing evidence; OpenSSL3.6.3 blocks its distribution.
Notarization, quarantined download/Gatekeeper, clean-machine and fresh provider
acceptance of the corrected runtime remain open.


The optional signing step requires a maintainer-approved Developer ID Application
identity and private-key access. Inspect available public identity metadata with
`security find-identity -v -p codesigning`; select the exact40-character certificate
fingerprint, rather than automatically using the first identity. Signing uses
Apple's secure timestamp service. From a reviewed clean source checkout:

```sh
python3 -B scripts/sign_macos_release.py /absolute/boss-0.1.0-rc.1.tar.gz \
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
| Provider | Baseline archive9596162 passed one Codex/Codex-review workflow through Done (3calls/100.875s). Fresh acceptance after the Git-registration runtime fix and other providers remain separate gates. |
| Distribution | Apache-2.0 included; local Developer ID signing and signed-payload smoke verified. Notarization and download acceptance remain open. Third-party notices retain their original licenses. |
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
