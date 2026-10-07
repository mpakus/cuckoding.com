# R017 — Cuckoding identity and layered Roman satire

Claimed from clean main `f589091`. Acceptance: [R017](../tasks/R017-layered-cuckoding.md).
Ponytail full 4.13.0 (MIT), imagegen, animate and quality-gates applied. No subagents.
RTK proxy exceptions: exact source reads, asset export, protocol/build output and
structural/browser-fixture checks must retain their original output semantics.

User corrections: full display name Cuckoding, abbreviated CC; Emperor always
capitalized. Existing private data paths/identifiers remain stable for continuity.
Scroll animation serves delight and explanation on the public marketing page;
native transforms and the existing motion controls suffice, with no new library.

Implemented Cuckoding/CC display names, capitalized Emperor copy and a cheeky
C/furcina tail mark. Regenerated SVG/favicons, PNG, ICNS and monochrome tray mask.
Preserved the existing data root, marker, executable and protocol identifiers.
Replaced flattened banquet/revels with 11 original imagegen assets (3 backgrounds,
8 RGBA cutouts), composed into four independently moving scenes. Retained the old
hero only for static social metadata. Original prompts and references: ARTWORK.md.

Reuse/reference: existing `site/site.js:1` motion preference/frame scheduling and
`bin/brand-icons:1` native export (this repository, Apache-2.0, base f589091).
No peer implementation or animation dependency was needed. Per-layer native
transforms preserve bounded background overscan and stationary accessible text.

Verification:
- `rtk proxy python3 bin/check-site`: PASS, 33 links/assets; four scenes/eight
  character layers, RGBA headers, accessible scene descriptions, names, scope,
  reduced-motion fallback, Pages boundary and icon consistency.
- `rtk proxy node --test test/site_test.mjs`: PASS, 4 tests for crossing approach,
  independent foreground movement, bounded depth, frame coalescing, all-layer
  pause, preference restore, denied storage and reduced-motion changes.
- Bundled Python/Pillow read-only alpha inspection: all eight foregrounds RGBA,
  min alpha 0, 44–72% transparent/near-transparent pixels. Original pixels kept.
- `rtk proxy bin/brand-icons` and a second exact export/hash comparison: PASS,
  every consumer byte-reproducible. Visually inspected icon and native tray PNG.
- `rtk mix format`; `rtk mix quality`: PASS, 30 ExUnit tests, compiler warnings
  gate, Credo, Sobelow and dependency audit. Existing Sobelow quoted-lock-key
  diagnostics remain tool warnings. Initial formatter failure repaired.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`: PASS.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked
  --all-targets -- -D warnings`: PASS.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`: PASS, 8.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/ccoding-r016-target bin/dev.build`:
  PASS, renamed `/private/tmp/ccoding-r016-target/release/bundle/macos/Cuckoding.app`.
  Alternate target avoids overwriting the earlier app bundle while in use.
- `rtk proxy env CCODING_RELEASE_DIR=/private/tmp/ccoding-r016-target/release/bundle/macos/Cuckoding.app/Contents/Resources/release CCODING_DATA_DIR=/private/tmp/cuckoding-r017-smoke-20261007 /private/tmp/ccoding-r016-target/release/bundle/macos/Cuckoding.app/Contents/MacOS/ccoding --smoke-test`:
  PASS, launch/bootstrap/cookie/replay/origin/heartbeat/graceful Quit/listener cleanup.
- CUA rendered inspection at 1280×900 and 390×844: clean transparent edges,
  crossed weapons with both gladiators visible, layered banquet/Pan/finale,
  keyboard pause resets all 12 layers, pause survives reload, no narrow overflow.
  Reduced motion and storage denial verified by runnable JS checks, not changed
  as a global OS preference. No-JavaScript content verified structurally.
- Current README/AGENTS/docs relative-link check and `rtk git diff --check`: PASS.

Screenshots are saved in the task visualization directory, including
`cuckoding-duel-desktop.png` and `cuckoding-finale-mobile.png`. This is local source
and a smoke-tested native bundle, not a replaced running app, public release,
push or Pages deployment. R020 connection/model/execution gates remain open.

