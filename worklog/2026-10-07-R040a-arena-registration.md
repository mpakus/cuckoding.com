# R040a — Arena registration

Claimed `tasks/R040a-arena-registration.md` from clean local main `396a36c`.
Ponytail full; LiveView, workflow, native shell, local runner, security and quality
skills applied. Acceptance is recorded in the task before implementation.

## Implementation and references

- Reuse the existing durable command dispatcher, event boundary, native helper
  executable, authenticated LiveView layout and immutable team revisions.
- Native AppKit `NSOpenPanel`, via already-locked objc2 0.6.5 / framework bindings
  0.3.2. Primary local source: objc2 revision
  `7b1abfd750a2cacaea71d6a56ecfb83cb7de560b`,
  `framework-crates/objc2-app-kit/src/generated/NSOpenPanel.rs:130` and
  `NSSavePanel.rs:435`. Adapted API usage only, not a peer workflow.
  Cuckoding adds bounded lifetime, parent-loss cleanup, durable intent and a
  separate registration confirmation. Local Cargo manifest confirms
  `Zlib OR Apache-2.0 OR MIT`; no upstream source was copied.
- `rtk proxy` is used for exact source reads, file-writing scripts, build/smoke
  output and native UI/build commands where filtering changes semantics.

## Result

- Authenticated Arenas screen, native folder selection, name/confirmation,
  expandable inherited team and durable registered-project list.
- Frozen revision references, unique path/device-inode identities and idempotent
  registration commands; subsequent defaults do not rewrite the inherited team.
- No project-content reads/writes, Git commands or agent launches. Git-entry
  observations are explicitly unverified. Selection has a two-minute native
  deadline, 135-second durable claim, cancellation and no interrupted replay.
- Shared grid uses shrinkable tracks/minimum widths; navigation scrolls inside a
  390-pixel page. Arena inputs reuse existing field styling; panels have spacing.

## Verification

- `rtk mix test test/cuckoding/arenas_test.exs test/cuckoding_web/arena_live_test.exs`:
  8 focused checks passed. Re-ran the affected focused tests after clean-env and
  stale-confirmation improvements. Coverage includes empty/docs/Git-entry fixtures,
  duplicate/replaced/symlink/protected paths, no file mutation, event canaries,
  frozen team revision, command replay/cancel/interruption, bounded helper output,
  clean environment/PWD/fixed arguments, expired sessions and recovered forms.
- `rtk mix quality`: **74 passed**, formatter/compiler with warnings as errors,
  Credo, Sobelow and dependency audit passed. Existing Sobelow/Elixir 1.20 quoted
  lockfile-key warnings remain tool diagnostics, not compiler failures.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`: passed.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`:
  passed on final Rust source.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`:
  **22 passed**, including canonical native directory-result checks.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r040a-target bin/dev.build`:
  passed. The isolated target leaves the older user's running native build intact.
- `rtk proxy python3 /private/tmp/cuckoding-r040a-proof-6r6___ob/verify-package.py`:
  final bundled fresh, copied four-migration upgrade and registered-Arena restart
  smokes passed: bootstrap/browser cookie/replay/origin/heartbeat/graceful Quit,
  five migrations, integrity `ok`, no FK failures, prior teams retained exactly,
  original prior DB hash unchanged, saved Arena retained. Native helper checks
  passed for an existing session leader and a newly owned group, explicit stdin
  cancellation and parent-pipe EOF; both exited within three seconds.
- CUA packaged UI: native selection produced a canonical existing-project
  preview; registration without confirmation retained the entered name/error;
  confirmed registration persisted, reload showed its five inherited roles and
  revision 3; running cancellation reached `cancelled`, with no helper left.
  Native panel AX targeting timed out, so the folder choice itself was not
  automated; returned native selection, browser confirmation and cleanup were
  verified. Later browser checks used an isolated IAB tab with a 60-second
  handoff fixture in the temporary DB; this is separate from native-auth smoke.
- Final packaged responsive check: `scrollWidth == clientWidth == 390`; default
  1280-pixel desktop and 390×780 rendering inspected. Viewport reset and IAB test
  tab closed. Screenshots: `/private/tmp/cuckoding-r040a-arenas-desktop.jpg` and
  `/private/tmp/cuckoding-r040a-arenas-narrow.jpg`. Catalog/model labels in the
  copied test team are fixtures, not real-provider evidence.
- `rtk proxy python3` local Markdown link/path validation: 22 files, zero missing
  targets. `rtk git diff --check`: passed.

## Fixes found during verification

- Clearing port environment initially supplied binary env keys; changed to
  Erlang charlists with no duplicate allowlist keys. The regression now checks
  a synthetic environment canary, private HOME and fixed helper arguments.
- First native launch refused Erlang's already-owned process group. Accept an
  existing group leader; otherwise establish the group. The final packaged
  lifecycle harness covers both launch forms.
- Prior-schema fixture initially had an empty marker and was correctly refused.
  Corrected only the copied fixture marker; upgrade passed and source hash stayed
  unchanged. One direct `cargo tauri` invocation selected old Cargo 1.83 and failed
  before compilation; `bin/dev.build` selects the pinned toolchain and passed.
- The first narrow inspection measured 501 pixels of page width at a 390-pixel
  viewport. Fixed the shared grid minimum sizing; final measurement is 390/390.

## Artifact and scope

Final bundle: `/private/tmp/cuckoding-r040a-target/release/bundle/macos/Cuckoding.app`.
Evidence root: `/private/tmp/cuckoding-r040a-proof-6r6___ob`; identity file
`identity-final.json`. SHA-256:

- native executable: `e89a134920955067b71f016be14c62a597bf6fb7002e04ded67cf70e12a94169`
- Arenas BEAM: `06e609cc027a32cc4ff652471af3c00248fe637e3929f2f8881cba4b796da3bd`
- ArenaLive BEAM: `f56bd80040ff11cff5847f7aa1b9069c7b7c775a1e195d58997f83d2a34a2b10`
- original copied-prior DB: `57d469cc7a806759e8b3073730db5c9dc4abf2b182744556c2255bebfe2b6806`

Final UI used owned shell PID 80725, release PID 80726, loopback port 59241.
All R040a owned test processes and listeners were verified closed after testing;
the retained DB has one registered Arena and zero pending/running/cancelling commands.
Test cleanup uses verified owned release SIGTERM and waits for native heartbeat
exit because native tray AX targeting is unavailable; bundled smoke independently
tests graceful shell Quit. Test data is retained. Earlier test ports 57328/57636
are closed. The older user-owned instance was not stopped or upgraded; a source
merge does not update that running build.

No remote push, Pages deployment or public release. Clean-machine/notarization,
physical sleep/wake and human-completed real-provider acceptance remain open.
Git validation/init/initial commit, team overrides, Tabulae and planning are the
next R040 slices. The native two-minute deadline was not a timed interactive drill.

## Local integration

Implementation commit `d1736e3` (`feat(arenas): Register local folders with frozen
teams`) was fast-forwarded into local `main` from `396a36c` with
`rtk git merge --ff-only feature/R040a-arena-registration`. The merged feature
branch was deleted using `rtk git branch -d feature/R040a-arena-registration`.
README, AGENTS and affected docs are included in that commit. This follow-up
records the completed local integration; no push or deployment was performed.
