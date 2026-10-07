# R016 — Trident identity and Roman revels

Claimed from clean main `606021f`. User explicitly requests trident/fork branding,
more satirical robot pleasure, satyrs/Pan, more scroll parallax and continued app
work. Acceptance: [task](../tasks/R016-trident-revels.md).

Apply Ponytail full 4.13.0 (MIT), imagegen, animate, local quality/security/native
skills. Use editable SVG for the existing vector identity; built-in imagegen for
new raster illustrations. No new framework or plugin. RTK proxy is used for exact
source, build/generation output and machine-readable validation. All shell entry
commands remain RTK-prefixed. Do not replace a running native bundle; build it to
an isolated target and record the distinction from the current runtime.

## Results and verification

- Original SVG trident/code mark, six deterministic consumers, tray template icon
  and explicit ICNS packaging. `rtk proxy bin/brand-icons` twice gives byte-identical
  hashes. Initial ICNS hash mismatch traced to unordered container chunks; sort
  chunks without changing pixels. Native glyph is visible in the site preview;
  no physical tray-pixel claim for the unlaunched new bundle.
- Two built-in imagegen outputs copied unchanged into site assets. First festival
  generation hit a network error; one retry succeeded. Final prompts retained in
  [Artwork](../docs/ARTWORK.md). Public captions/alt text identify satire.
- Three bounded scroll scenes, counter-moving stamps, persistent global pause and
  reduced motion. New images load lazily. Text remains static. Adjusted image
  framing after rendered inspection to preserve the performers.
- `rtk mix format` and `rtk mix quality`: pass, **22 tests**, compiler, Credo,
  Sobelow and dependency audit; same upstream lockfile-parser warnings as R010.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml`, Clippy with
  `--locked --all-targets -- -D warnings`, and `cargo test ... --locked`: pass,
  **4 native tests** (all commands RTK-prefixed).
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/ccoding-r016-target bin/dev.build`:
  pass, including a repeat build after deterministic ICNS normalization. New
  bundle at `/private/tmp/ccoding-r016-target/release/bundle/macos/CCoding.app`;
  existing running foundation bundle was not replaced or restarted.
- Packaged `--smoke-test` with that bundle's release path and isolated
  `/private/tmp/ccoding-r016-smoke`: pass launch/auth/cookie/replay/origin/heartbeat/
  owned quit/listener cleanup; no live provider or physical tray click implied.
- `rtk proxy python3 bin/check-site`: pass, 24 references and three scenes.
- `rtk proxy node --test test/site_test.mjs`: **3 passed**, now exercises all three
  scene transforms and system/user pause. `node --check site/site.js` passes.
- Computer use: original desktop width 862 and narrow 390, no document overflow;
  new banquet/festival scenes render, all images load, global pause sets every
  displacement to zero. Existing R015 navigation/board remains unchanged.
- `rtk git diff --check`: pass. README, AGENTS, plan, product and site docs updated.
  Local merge only; no push or Pages publication. Continue R020 next.
