# R100a — Current local beta artifact

Claimed after R080g merged into local main as d549f8c and its branch was deleted.
Ponytail full 5.3.2 (MIT), menubar-shell/local-runner/security/quality and installed
verification guidance apply. RTK proxy preserves exact build/native output.
Untitled.md.age remains untouched. No provider inference is authorized by these
offline checks and no release/push/publication is performed.

Preflight: no running executable under Cuckoding.app/CCoding.app was observed.
The historical R050c data root still has two Arenas/two boards/two tasks and 285
events; integrity/FKs pass, 71 setup commands settled, no battles. Its ownership
marker, shell lock and prior launcher are absent. Do not recreate them or launch
that unrecognized root. Existing Codex/c2 are disconnected and Cursor reports
not_connected. Preserve all contents; use a new isolated smoke root and request
the user's current recognized workspace for subsequent account acceptance.

## Packaging repair and verification

Strict verification of the first rebuilt bundle failed: `code has no resources
but signature indicates they must be present`. The helper had only a linker
ad-hoc signature, with unbound Info.plist and no resource envelope. Seal the
complete development bundle after Tauri copies its resources, then verify it;
the standalone native helper cannot establish bundle-resource integrity.
`bin/smoke` now refuses an unverified bundle before creating/launching a fixture.
Apple's [distribution-signing guidance](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)
and [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/)
describe outer signing after nested code and strict/deep verification. The local
identity remains explicitly ad-hoc; no Developer ID/notarization claim is added.

- `rtk proxy env PATH=<pinned toolchains> bin/dev.build`: pass after repair;
  production assets/release/native application rebuilt with the locked packages.
  OpenSSL relocation emits its expected invalidated-signature warnings, followed
  by signing. Hex's update notice is not a dependency failure.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`: pass.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`: pass.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`: first
  run passed 79 tests, five deliberately ignored, in 219.63 seconds. RTK buffered
  output; a read-only process sample showed the retained-integration Git test,
  not a crashed process. An exact-output final run uses `rtk proxy cargo test`
  so slow individual tests remain observable: 79 passed, zero failed, five
  ignored, 221.03 seconds on the final source. The three native battle Git tests
  reported over 60 seconds and all completed; no tests were disabled or killed.
- `rtk proxy bin/smoke`: pass on the final sealed bundle, including the added
  global-dashboard unauthorized/authenticated checks and existing routes, cookie,
  handoff/origin refusal, heartbeat, graceful quit and listener cleanup. Final
  fresh root `/private/tmp/ccoding-smoke.ZqLanp` retained.
- Copied bundle signature test: original and private copy verify, then changing
  the copy's `releases/start_erl.data` fails strict verification with exit 1.
  Receipt retained in `.ccoding/r100a-validation/signature-31awwfba/`.
- Final signed helper SHA-256:
  `39b42c5fb37a4f51332bcf2f61714e2f4d54fbd648919eb82b55b84d05674906`.
- `rtk proxy sh -n bin/dev.build bin/smoke` and `rtk git diff --check`: pass.
- Modified Markdown local-file references: pass.

Artifact: `desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`, from
`d549f8c` plus this slice's dashboard-smoke assertion and packaging commands.
The suite compiles with Rust 1.97.1 on arm64 macOS. No new Rust runtime logic,
dependencies, grants or migration is introduced. The prior R080g 408-test Mix
quality result covers the unchanged Elixir source; no new full-Mix run is claimed.

## Retained-data copy

Online SQLite backup of the read-only original passes integrity/FKs and matches
its full dump SHA-256:
`aa5ba20b427c49f1281c4be5adc0826671c69bb724f5eec0a46829449425d1c3`.
The exclusive backup and receipt remain under
`.ccoding/r100a-validation/pre-upgrade-0e3375d0-a6dc-459a-be4c-1d25ed7d23f6/`.
Create a new private recognized fixture root and copy only that database, never
profiles. The current bundled helper's `--smoke-test` opens and shuts it down.
Eleven migrations become fourteen; integrity remains ok and FK violations zero.
Hashes of all saved agent/Arena/board/task/team/command/check/battle/attempt rows
remain identical. Only browser tokens (+1), shell events (+4), and migration
records (+3) change; the workspace row is identical. Original database dump hash
is unchanged afterward. Receipt and before-table hashes are retained under
`.ccoding/r100a-validation/retained-data-jlq35bkp/`.

This profileless copied-data smoke is not login persistence or original-workspace
relaunch acceptance. A pending user decision covers restoring recognition/launcher
for the original root versus a new workspace; neither action is inferred from
elapsed time. The original has not been launched, reset, migrated or remarked.

## Review and remaining gates

Reviewed build ordering, failure propagation (`set -eu`), no automatic Developer
ID selection, smoke before native launch, complete-resource mutation refusal,
session/handshake behavior and data-root isolation. No code condition was added;
the negative resource mutation is the concrete regression experiment. The dirty
encrypted user file is excluded. No push or publication.

Still open: real Codex/Cursor task/battle/parallel acceptance, broader execution
and recovery grants, physical sleep/lease tests, timed unfamiliar-user setup,
Developer ID/notarization, reproducibility, clean-machine install and signed
update/rollback. Local signature/smoke/upgrade success closes none of those gates.
