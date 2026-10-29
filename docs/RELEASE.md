# BOSS 0.1.0-rc.1

Status: local macOS release candidate under verification. No public release, tag,
signature/notarization or remote CI result is implied by this document. Results
and remaining gates are recorded in [.worklog/2026-10-29.md](../.worklog/2026-10-29.md).

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
| Provider | Explicit bounded Codex workflow and selected reviewer through checks/integration/Done; sanitized receipts only. |
| Distribution | Project license chosen, third-party notices reviewed, signing/notarization completed and download acceptance. |
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
