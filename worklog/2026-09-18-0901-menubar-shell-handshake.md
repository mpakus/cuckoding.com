# Worklog — 0901 menubar shell and handshake

## Metadata

- Date/time (UTC): 2026-09-18
- Task: 0901
- Status: complete
- Human/agent owner: codex
- Branch: `feature/0901-menubar-shell-handshake`
- Start revision: `7c1b7be`
- End revision: task commit

## Acceptance criteria

- Promote the proven Tauri tray shell into a production project with no Dock
  icon or native window.
- Launch the bundled release with credentials only in a unique mode-0600 file,
  accept exact readiness, poll status, and own bounded shutdown/crash cleanup.
- Add loopback-only Phoenix shell endpoints with one-time bootstrap exchange,
  single-use expiring browser tokens, authenticated browser sessions, and safe
  local redirects.
- Run the configured hibernate/stop policy before shell shutdown.
- Cover unauthorized access, token replay, pre/post-ready crashes, quit with
  running work, and a clean-machine launch in proportion to the available host.

## Reference coding

- Focused project and Hydra XERJ searches were attempted first; the configured
  loopback node was unavailable.
- Pinned MIT Hydra revision `d8ad56112c2c3acfb2f65f53b6890f30a25c693c`
  uses bounded startup with early-exit detection and graceful daemon shutdown
  before a forced process stop at `electron/daemon/lifecycle.ts:32-124`.
  Cuckoding adapts the lifecycle shape, not source, while retaining a mode-0600
  credential file, exact READY payload, loopback authentication, process-group
  ownership, and durable run policy.
- The already verified task 0003 spike is the primary local reference. Its
  measured contract is recorded in `docs/MENUBAR_SHELL_SPIKE.md`.

## Work performed

- Claimed Task 0901 and restated its acceptance criteria.
- Promoted the proven Tauri spike into the pinned production project under
  `desktop/`, with Accessory activation, no native window, the required tray
  menu, status polling, About metadata, log access, exact READY parsing, early
  failure cleanup, crash status, and the bounded process-group shutdown ladder.
- Removed credential-derived filenames. The shell now creates a random,
  non-symlink-following mode-0600 credential file and log inside a mode-0700
  data directory, passes only the file path to the release, and cleans up the
  file on every startup exit path.
- Added release migration bootstrap, an allowlisted sterile child environment,
  random loopback port selection, disabled BEAM distribution, and a bundled
  SQLite path.
- Added the Phoenix one-time bootstrap exchange, in-memory shell capability,
  60-second single-use browser tokens, fail-closed browser LiveView hook,
  strict IPv4 loopback host/origin plug, safe redirect allowlist, authenticated
  status, and a generic shutdown error surface.
- Connected Quit to the existing durable board/lifecycle path: admission pauses,
  active runs hibernate, and shutdown is rejected if hibernation fails. A
  port-owning run without its live lease handle is rejected before its process
  is stopped, avoiding a partial transition.
- Added focused authentication, symlink/permission, replay, origin/host,
  browser-session, real hibernate, unsafe-port, shutdown-order, and
  shutdown-refusal coverage.
- Added the production build and sterile verifier, updated shell/security/
  distribution/development docs, and marked the Phase 9 shell item complete.

## Verification

| Check | Result |
| --- | --- |
| Focused Phoenix shell/auth/policy tests | pass; 9 tests, 0 failures |
| Pinned Rust `cargo fmt`, `cargo test`, and `cargo clippy -D warnings` | pass; 4 tests, 0 failures; no lint warnings |
| `rtk proxy sh desktop/build.sh` | pass; production Phoenix release and unsigned local `Cuckoding.app` built; 22 sterile protocol checks passed, including pre/post-READY failure cleanup |
| Native bundle inspection and launch | pass; arm64 Mach-O, `LSUIElement=true`, one BEAM listener on `127.0.0.1`, exact shell and child exited after `SIGTERM`, listener released |
| `rtk mix quality` | pass; 10 properties and 185 tests, 0 failures; Credo checked 166 files/2,469 functions and macros with no issues; Sobelow and dependency audit passed |
| `rtk git diff --check` | pass |

The first full quality run hit one transient `database is locked` failure in the
pre-existing concurrent event-store property. The isolated property immediately
passed, and subsequent full quality runs passed; it is not reported as an
implementation failure.

`rtk proxy` was used where exact unfiltered build output or the pinned Rust
toolchain/environment was required. Product command configuration remains
unwrapped.

## Handoff

Task complete after final review and local-main merge. The produced `.app` is a
local unsigned artifact only. Developer ID signing, nested ERTS/NIF signing,
entitlements, notarization, stapling, SBOM, and clean installed-Mac evidence
remain Task 0902 and must not be inferred from this result.
