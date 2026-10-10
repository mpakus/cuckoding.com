# R019a · Sci-fi gothic artwork

2026-10-10. Clean main at `1b1f623`; claimed `feature/R019a-goth-artwork`.
User requests sci-fi goth and BDSM-inspired ideas in the pictures. Interpret as
non-explicit alternative fashion: leather tailoring, harness-style hardware,
collars, decorative chains and spikes on clothed adult characters/robots, with
gothic sci-fi architecture and green light. Preserve the existing scene layout,
parallax, pause/reduced-motion controls and truthful product claims.

Reach: four original generated images (emissary, vault, Pan, revelers), public
image descriptions, artwork/site/plan documentation, README and AGENTS. Use the
built-in image editor and retain real foreground alpha. No new JavaScript,
dependency, application behavior or provider operations.

Ponytail full 5.1.0 (MIT). All shell commands use RTK; `rtk proxy` preserves exact
file inspection and native script semantics.

## Result and verification

Four built-in imagegen edits replaced the corresponding originals in
`site/assets/`. Old art is retained in Git at `1b1f623`; exact edit prompts and
inputs are documented in `docs/ARTWORK.md`. Scene accessible descriptions now
describe the new costumes/architecture, including the finale's reused robots.
No motion code, layout or application behavior changed.

Read-only Pillow checks confirmed identical dimensions to each input, correct
RGB/RGBA modes and real alpha (percentage of pixels with alpha below 16):

| Asset | Dimensions | Bytes | Near-transparent pixels |
| --- | --- | --- | --- |
| neon-emissary.png | 1024×1536 | 2,912,737 | 30.9% |
| neon-vault.png | 1536×1024 | 2,493,215 | Opaque background |
| neon-pan.png | 1254×1254 | 1,182,348 | 73.9% |
| neon-revelers.png | 1536×1024 | 1,799,855 | 78.4% |

- `rtk proxy python3 bin/check-site`: PASS, 35 links/assets, scope/provenance,
  accessibility structure, motion fallback and Pages boundary.
- `rtk proxy node --test test/site_test.mjs`: all 5 tests passed.
- `rtk git diff --check`: passed.
- Changed documentation local-link validation: passed.
- CUA rendered review at 1440×1000 and 390×844: hero and afterparty compositing,
  legible copy, preserved transparent edges, all edited images loaded, no page
  horizontal overflow. Narrow finale reuse inspected. Pause reset all afterparty
  layer transforms and was resumed; no browser errors were reported.
- Screenshots: `/private/tmp/cuckoding-r019a-visual/desktop-hero.png`,
  `desktop-afterparty.png`, `mobile-hero.png`, `mobile-afterparty.png`.

Physical mobile/Safari and OS reduced-motion toggling were not repeated. Existing
Node preference tests passed; native app tests/build were not run for this
artwork-only change. No new tests mirror unchanged logic.

## Integration

Commit and fast-forward merge to local main, then remove the task branch. Keep
the existing loopback preview at `http://127.0.0.1:4387/`; no push/deployment or
native app restart. Docs, README and AGENTS updated with the resulting direction.
