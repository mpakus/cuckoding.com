# Worklog — 0904 login item and diagnostics bundle

## Metadata

- Date/time (UTC): 2026-09-18
- Task: 0904
- Status: complete
- Human/agent owner: codex
- Branch: `feature/0904-login-item-diagnostics`
- Start revision: `2e7dac6`
- End revision: recorded by the Task 0904 commit

## Acceptance criteria

- Provide an explicit, inspectable login-item toggle without adding a second
  native application framework.
- Keep the existing native About panel and expose accurate version and release
  information.
- Generate a private, user-reviewed diagnostics archive containing bounded
  versions, allowlisted configuration, migration status, plugin health, power
  events, normalized recent errors, and process summaries.
- Exclude repository source, prompts, credentials, raw command output, and full
  environment or argv values.
- Pass canary, path-confinement, structural, and production-bundle checks.

## Reference coding

- Focused XERJ project, Hydra, and Vibe Kanban searches were attempted before
  implementation. The documented loopback node was unreachable, so indexed
  retrieval is explicitly degraded and pinned source inspection is used.
- Pinned Hydra revision `d8ad56112c2c3acfb2f65f53b6890f30a25c693c`
  is MIT licensed. Its bounded, settings-triggered diagnostics export at
  `electron/observability/ObservabilityService.ts:73-133` and
  `src/components/Settings/SettingsPanel.tsx:723-746` informed only the explicit
  user action and completion status. Cuckoding replaces Hydra's selectable
  log/database export with a fixed privacy allowlist and no sensitive toggle.
- Apple's `SMAppService.mainApp` registration/status API is the platform
  boundary for the macOS 13+ login item. The pinned
  `objc2-service-management` 0.3.2 binding is Zlib/Apache-2.0/MIT licensed.

## Work performed

- Added a native `SMAppService` check-menu toggle whose label and check state
  expose enabled, unregistered, approval-required, and unavailable states.
- Kept the existing native About panel and added an authenticated menubar
  diagnostics action that accepts only a regular file beneath the application
  data diagnostics root before revealing it in Finder.
- Added an owner-only, atomic ZIP exporter with a fixed seven-file schema,
  200-row query bounds, a 2 MiB uncompressed-input cap, shared redaction, and
  symlink rejection. Source, prompts, provider output, credentials, raw logs,
  command output, argv, environment, private paths, manifests, and free-form
  errors never enter the schema.
- Added settings disclosure and explicit export, shell authentication, focused
  canary/path/UI/controller coverage, and packaged normal/safe-mode checks.
- Updated shell, architecture, security, distribution, task, and plan docs.

## Verification

- `rtk mix test test/cuckoding/diagnostics_test.exs test/cuckoding_web/shell_controller_test.exs test/cuckoding_web/plugin_settings_live_test.exs`
  — 12 tests, 0 failures.
- `rtk mix quality` — 10 properties and 199 tests passed; formatter/compiler,
  Credo, Sobelow, and Hex audit passed with no findings. The first run found
  three style issues after tests passed; they were fixed before this clean run.
- `rtk proxy env -u GEM_HOME -u GEM_PATH PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/ruby desktop/release_metadata_test.rb`
  — 6 runs, 15 assertions, 0 failures.
- Pinned Rust 1.90 `cargo test` — 9 tests passed, including native login status
  lookup; `cargo clippy --all-targets --all-features -- -D warnings` passed.
- `rtk proxy sh desktop/build.sh` — production release and Tauri `.app` built;
  the sterile verifier passed the existing startup, authentication, shutdown,
  crash, safe-mode, and update/rollback drills plus the fixed diagnostics
  entries, launch-token exclusion, owner-only mode, and safe-mode export.
- `rtk git diff --check` — passed.
- RTK proxy exceptions were limited to exact build/release streams and the
  repository's sterile-environment commands, where filtering changes command
  semantics; no product configuration stores an RTK wrapper.

## Handoff

Complete. The login-item registration requires a signed installed application
for end-user enablement; the native status API, menu mapping, bundled release,
and application protocol are verified locally. Apple notarization remains the
release pipeline's separate deployment gate and its credential is not stored in
the repository.
