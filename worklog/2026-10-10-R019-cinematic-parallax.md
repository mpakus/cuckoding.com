# R019 · Cinematic Arena scrolling

## Scope and reference

2026-10-10. Clean local main at `503e741`; claimed `feature/R019-cinematic-parallax`.
Adapt the user-requested https://www.1367studio.com/ composition and motion ideas,
using only original Cuckoding artwork. Browser inspection found a full-viewport
portrait, sticky camera approach, floating navigation and spacious editorial
sections. No reference assets, code, fonts or text are copied.

Reach: `site/index.html`, `style.css`, `site.js`, original assets, site structural
and motion checks, artwork/site/plan docs, README and AGENTS. Internal app code,
provider connections and data are outside this visual slice.

Use the existing native scroll/RAF path; no animation dependency. Preserve
content and controls without motion/JavaScript, independently layered satire,
and implemented/planned product claims. All repo commands use RTK; `rtk proxy`
retains exact source/script output and native Node/Python semantics.

## Verification

- `rtk proxy python3 bin/check-site`: PASS, 35 links/assets, accessibility
  structure, scope/provenance, motion fallback and Pages boundary.
- `rtk proxy node --test test/site_test.mjs`: 5 tests passed. Includes bounded
  reversible camera depth, short-frame clamping, pause geometry, all existing
  layer motion, frame coalescing, denied storage and live reduced-motion changes.
- `rtk proxy node --check site/site.js`: passed.
- `rtk git diff --check`: passed.
- CUA browser inspection at 1440×1000 and 390×844: hero and camera close-up,
  full-width crossing duel, editorial/staggered roles, main section navigation,
  no horizontal page overflow, no failed loaded images, no browser errors.
  Narrow board keyboard scrolling moved 40 px and retained focus. Main section
  headings cleared the fixed navigation (120 px desktop / 145 px narrow).
- Pause preserved scroll offset 877 and hero height 1850, reset motion, and
  persisted across reload; resumed before handoff. Image framing/header and
  pause/duel-label overlap found during inspection were corrected.
- Saved proof: `/private/tmp/cuckoding-r019-visual/desktop-hero.png`,
  `desktop-camera.png`, `mobile-hero.png`.
- Built-in imagegen created `neon-emissary.png` (1024×1536 RGBA, 3,016,423 bytes,
  30.6% near-transparent pixels) and `neon-vault.png` (1536×1024 RGB, 2,319,030
  bytes). Read-only Pillow inspection confirmed alpha/dimensions; original
  bytes copied into `site/assets/`. Full prompts retained in `docs/ARTWORK.md`.

Ponytail full 5.1.0 (MIT); native CSS/JS reused, no new dependencies. Motion has a
clear scene-depth purpose and uses bounded transforms only, with no idle loop,
scroll interception, text animation or hidden content. No-JS normal flow was
source-checked; reduced motion was exercised in Node, not toggled in the OS UI.
Physical mobile/Safari and bandwidth/performance profiling were not run. Native
app tests/build were not repeated for this site-only slice; app/data unchanged.

## Integration

Commit and fast-forward merge to local `main`; delete the completed task branch.
Only local source and the existing loopback preview are changed. No push, Pages
publication or native app restart. Preview: `http://127.0.0.1:4387/`.
