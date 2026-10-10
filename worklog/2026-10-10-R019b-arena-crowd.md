# R019b · Gothic Arena spectators

Claimed on clean main 462eb9d; feature/R019b-arena-crowd.
Scope: requested site/assets/neon-arena.png, reused behind duel/afterparty/finale,
its accessible scene descriptions and artwork provenance. The independent
foreground layers and motion behavior remain unchanged.

Use built-in imagegen to edit the existing plate, Ponytail full 5.1.0 (MIT),
and quality-gates. RTK proxy preserves exact script/source and image metadata
output. No image post-processing, new dependency or remote publication.
Acceptance: tasks/R019b-arena-crowd.md.

## Result

Built-in imagegen edited the original background with more readable adult
spectators wearing leather harnesses, ring hardware, collars, cuffs and waist
chains. Crowds stay in the terraces; the empty foreground, central portal,
black/green palette and separate foreground assets are preserved. The exact
prompt and input revision are in docs/ARTWORK.md. Original generated output:
`/Users/mpak/.codex/generated_images/01a11422-7a5a-7251-87cb-1d8f8b8e5fd4/exec-3d2ffaf8-2e24-4e41-aa70-fb108f902b59.png`.
Copied without pixel post-processing to `site/assets/neon-arena.png`.
Prior version remains in Git at 462eb9d.

The three reused scene labels describe the updated spectator costumes. Docs,
README and AGENTS record the composition and scope. No layout, JavaScript,
application behavior, dependency or provider operation changed.

## Verification

- Read-only PNG IHDR check: opaque RGB, 1536×1024, 2,476,285 bytes (under 6 MB).
  SHA-256: `373c6708b10c745c3d1f90ac986820afffd75ebba9fd6f1c7e29a5a5f9dc1d97`.
  Pillow was unavailable in default Python; used standard-library PNG metadata
  inspection instead, without installing a dependency or changing image bytes.
- `rtk proxy python3 bin/check-site`: passed 35 links/assets and existing scope,
  provenance, accessibility, motion-fallback and Pages-boundary checks.
- `rtk proxy node --test test/site_test.mjs`: all five tests passed.
- CUA desktop 1440×1000: revised crowd visible behind the crossing gladiators,
  clear foreground composition, all three background instances loaded at their
  expected dimensions, no page horizontal overflow.
- CUA narrow 390×844: afterparty and finale composites retain independent
  characters and cropped background, readable content and no horizontal overflow.
  No browser errors. Temporary viewport restored.
- Screenshots retained in `/private/tmp/cuckoding-r019b-visual/`:
  `desktop-arena.png`, `mobile-afterparty.png`.
- `rtk git diff --check` and changed-document local-link checks passed.

Physical-device/Safari and manual OS motion toggling were not repeated. Existing
motion tests passed. Native app build/tests were skipped for this artwork-only
slice; no native restart was needed. Static preview remains on port 4387.

Commit and fast-forward merge to local main; delete the merged task branch.
No push or public deployment.
