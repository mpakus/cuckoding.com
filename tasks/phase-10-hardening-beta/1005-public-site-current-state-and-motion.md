---
status: done
owner: codex
started_at: 2026-09-19
completed_at: 2026-09-19
worklog: worklog/2026-09-19-1005-public-site.md
---

# 1005 — Sync the Public Site with the Current Product

## Objective

Update the dependency-free GitHub Pages site so its product flow and feature
claims match the current controlled-beta implementation, then add restrained
marketing-page motion and parallax without weakening accessibility or the
honest trusted-host boundary.

## Dependencies

- Task 1003's current local implementation and evidence ledger. This site sync
  may proceed while the external controlled-beta observations remain pending.

## Scope

- Update `github.page/` copy for the landed project, board, task, prepared-run,
  dashboard, Agent Floor, knowledge, plugin, and native-shell surfaces.
- Keep controlled-beta enrollment, signed distribution, and external dogfood
  evidence visibly pending.
- Reuse the existing artwork and dependency-free CSS/JavaScript.
- Add transform-only decorative parallax and one-shot reveal polish with a
  complete reduced-motion path.
- Present the wide concept artwork as section backgrounds and use every
  `person*.webp` asset as a decorative parallax foreground layer.
- Preserve the finale composition as the reference treatment and link the
  requested Austin/Texas footer credit to `https://aomega.co`.
- Keep the adjacent truth and finale scenes from repeating the same character.
- Do not deploy, publish a release, or claim production readiness.

## Acceptance criteria

- [x] Public copy distinguishes current local features from pending external
      beta and signed-distribution gates.
- [x] Project → board → task → prepared run and operational monitoring match
      the implemented routes and documentation.
- [x] Motion uses native browser features, keeps readable content stable, and
      disables parallax when reduced motion is requested.
- [x] The page remains semantic, keyboard accessible, and free of horizontal
      overflow at 320 CSS pixels.
- [x] JavaScript syntax, the focused site verifier, whitespace checks, and
      desktop/mobile browser checks pass.
- [x] Wide concept scenes render as section backgrounds, all six person assets
      move as scroll-parallax foreground layers, and the finale stays intact.
- [x] Footer credit exactly matches the requested wording and destination.
- [x] The truth scene uses a different character from the finale's left edge.

## Verification and evidence

Run `node --check github.page/script.js`, `ruby github.page/verify.rb`, focused
source assertions, `git diff --check`, and browser checks at desktop and 320 px.
