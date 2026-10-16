# R060i worklog · 2026-10-15

Claim: `tasks/R060i-idle-sleep-lease.md`; branch `fix/R060i-idle-sleep-lease`.
Began on clean main at `96c2b33`, 29 commits ahead of origin/main.

Acceptance: durable bounded work eligibility, authenticated shell decision,
fixed timed native assertion, verified release/timeout and honest observed status;
no role/provider grant, permanent setting change or physical-sleep claim.

Using Ponytail full 5.2.0 (MIT), local-runner, menubar-shell, architecture,
security-review and quality-gates. Reuse the existing shell heartbeat, SQLite
events and LiveView Settings; no new process launcher or dependency. `rtk proxy`
preserves exact source, protocol and test/build evidence.

Primary API evidence: installed Xcode MacOSX.sdk IOKit `pwr_mgt/IOPMLib.h`,
lines277–292 (idle-system scope/forced-sleep limitations), 443–491 (preferred
creation API and default timeout turn-off), 662–675 (release/properties), and
787–798 (bounded timeout behavior). No peer implementation copied. Record SDK
identity and final evidence below.

SDK identity: `rtk proxy xcrun --show-sdk-version` → 27.0. Explicitly pass
TimeoutActionTurnOff rather than relying on its documented default. The first
native test incorrectly expected `AssertLevel` to change after timeout; it failed
twice (default and explicit action). Apple's daemon moves the assertion to the
inactive list without rewriting that declared property. Corrected the test to
verify this process's exact assertion ID is initially active, leaves the active
list after its one-second fixture timeout, stays owned, and disappears on release.
The final native timeout test passes; no physical sleep requested.

Primary references: [Apple API](https://developer.apple.com/documentation/iokit/1557078-iopmassertioncreatewithdescripti)
and [PowerManagement](https://github.com/apple-oss-distributions/PowerManagement/blob/d415e45501842834a280930c3eed9186544a67f0/pmconfigd/PMAssertions.c#L3914-L3966),
revision `d415e45501842834a280930c3eed9186544a67f0`, `PMAssertions.c:3809–3814,
3914–3966` (inactive-list timeout), `1153–1166` (active/properties queries).
APSL-2.0 source inspected, no source copied or vendored. GitHub revision lookup
via Python's TLS failed on the local certificate chain; normal TLS-verified
`rtk git ls-remote` succeeded. No certificate checks disabled.

Implemented: DB-derived eligibility and frozen policy; exact shell-only boolean/
lease contract and fixed native report header; one owned timed IOKit assertion;
nonfatal API failure/no accumulation; change-only normalized audit; Settings
last-report/time/age/stale display and restart Unknown. No migration/dependency.

Verification so far:
- Focused `rtk proxy env PATH=<pinned toolchain path> mix test
  test/cuckoding/shell_auth_test.exs test/cuckoding/battles_test.exs
  test/cuckoding_web/controllers/shell_controller_test.exs
  test/cuckoding_web/foundation_live_test.exs`: 87 passed.
- `rtk proxy env PATH=<pinned toolchain path> mix quality`: 362 passed; format,
  warning-as-error compile, Credo, Sobelow and dependency audit passed. Sobelow's
  existing quoted-keyword lockfile parser warnings remain; no vulnerabilities.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked
  power::tests -- --test-threads=1`: 3 passed; real owned IOKit timeout/release.
- Same Cargo command with `service::tests -- --test-threads=1`: 6 passed;
  closed contract/header refusal, fixed reports, idle/protocol/backend-exit release.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked
  --all-targets -- -D warnings`: passed.

The pinned PATH above is
`/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/opt/homebrew/opt/erlang/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`.

Restart: CUA `getApp(com.cuckoding.rebuild)` again timed out. Applied Development's
previously authorized idle-only fallback after verifying native 98510/backend
98513 (both started Thu Oct15 18:19:03 2026), exact bundle executables, parent,
repo/data cwd and loopback 51252. Saved workspace integrity/FKs passed, with
zero active commands/battles; private online backup
`.ccoding/r060i-validation/before-rebuild.sqlite3` has 11 migration rows,
2 named connections, 2 team revisions, 2 Arenas and 242 events. Bound SIGTERM to
the backend's audit token after repeating identity/idle checks; normal backend
and heartbeat-driven shell exits and listener closure verified, no escalation.
This fallback does not emit the tray Quit event. Saved launcher/data root retained.

Final verification:
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`:
  79 passed, 5 ignored, 228.31 seconds. Optional real-runtime/canary gates were
  not enabled; ignored is not passing evidence.
- `rtk proxy env PATH=<pinned toolchain path> bin/dev.build`: passed. Assembled
  production release and packaged native app rebuilt; 73 application ebin files
  match byte-for-byte between the assembled and bundled release. OpenSSL relocation
  warnings were followed by the build's existing ad-hoc signing, not release signing.
- `rtk proxy bin/smoke`: passed in `/private/tmp/ccoding-smoke.dS34nu`.
  Same packaged `--smoke-test` against `_build/prod/rel/cuckoding`, in isolated
  `/private/tmp/ccoding-r060i-source-fu7xdimd`: passed. Both verify authenticated
  launch, handoff replay/origin/cookie refusal, protected app routes, heartbeat,
  graceful Quit and listener cleanup. Each DB retains exactly one normalized
  Released observation plus Quit; no provider runs.
- Local Markdown references in all 13 changed instruction/docs/task/worklog
  files resolve; `rtk proxy git diff --check` passed.

Saved launcher reopened the exact same data root. Native 55406/backend 55407,
started Thu Oct15 22:11:39 2026, bind only `127.0.0.1:62621`. Integrity/FKs passed;
all 14 non-event/non-session tables match the backup exactly, including
connections, selections, team bindings, commands, drafts and Arena data. All 242
old events remain unchanged; additions are only shell/browser authorization and
one `shell.power_observed` Released event. No provider sign-in/use or substitution.

Chrome native accessibility and screenshot inspection succeeded after relaunch:
Settings renders the last Released report, UTC time, updating age/Recent and
explicit limitations in the existing black/green one-panel layout. No extra setup
controls. The tray-specific automation call still timed out; physical sleep/wake,
narrow-viewport polish, active-provider Quit/recovery, real battle/provider
acceptance, clean-machine signing/install/update and parallel workers were not
exercised here. The app is left running with the user's saved workspace.

Final self-review tightened freshness to use the greater UTC/monotonic age and
mark backward time stale. A suspended monotonic clock cannot make an old report
recent after wake. Added forward/backward UTC regressions; full Mix quality
rerun passed with the same 362 tests and static/dependency checks. Rust sources
are unchanged since the passing 79-test native suite. Repeated idle-only normal
shutdown after exclusive backup `before-final-rebuild.sqlite3` (245 events), exact
55406/55407 identity/cwd/start checks and audit-token SIGTERM; both processes and
listener 62621 closed normally. Rebuild/relaunch below supersedes the earlier
running-artifact identity, not its retained evidence.

Final `bin/dev.build`, packaged smoke (`/private/tmp/ccoding-smoke.cZexWz`) and
source smoke (`/private/tmp/ccoding-r060i-final-source-34jhzph4`) passed again.
The saved launcher now runs native 56624/backend 56625, started Thu Oct15
22:15:50 2026, at `127.0.0.1:62980`. Compared against the final backup: all
14 saved tables and all 245 existing events unchanged, only the same three
allowed lifecycle/power events added. Integrity/FKs and 73 bundled application
ebin files match. The saved connection/profile/model/team selection is intact.

Final Settings accessibility inspection verified Released/time/age/Recent and
scope text; closed only the stale tab created by the earlier preview launch.
A browser reload attempt was interrupted by user control, so its visual result
is not claimed. Reconnect/stale/unavailable/clock-discontinuity coverage remains
the passing LiveView/domain regressions; no further browser action was sent.

Implementation `03bd5d8` fast-forward merged into local `main`; merged branch
`fix/R060i-idle-sleep-lease` deleted. Docs/AGENTS/README updated with the implemented
scope and remaining gates. No push, deployment, provider usage or data/profile
substitution. Final `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml
--check` and staged/unstaged whitespace checks passed.

Next R060 work: broader interrupted native/process ownership reconciliation,
resource-lease/active-time accounting and physical sleep drills, then R070 parallel
workers/combined-result review. General toolchain checks, live provider/mixed-team
acceptance and release verification remain open in PLAN; this slice closes only
bounded native idle-sleep protection and its observational UI.
