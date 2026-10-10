# R018 · Neon Arena design

Claimed clean main 738f8ee on feature/R018-neon-arena-design.
Scope: static site HTML/CSS/asset composition/motion tests, shared app CSS and
small workspace presentation, current claims/provenance/docs. No provider or DB changes.
User references are visual inspiration only: obsidian/chrome cyborgs, electric
green seams, dark HUD frames, synthwave grids. Do not copy reference watermarks
or imply licensed franchise characters. Preserve C/furcina logo and role vocabulary.
Ponytail full 5.1.0 MIT, UI design, imagegen and quality-gates apply.
RTK for shell commands; proxy for exact source/scripts/images/build output.

Implemented:
- Original black/chrome/green orbital Arena, six transparent character assets and
  four independently layered scenes. Reused assets in role cards and social preview;
  removed superseded painted assets from Pages (recoverable in Git history).
- Native HTML/CSS/JS, black/green shared palette, sharp panels, readable system type;
  coordinated app navigation, controls and mobile input sizing. No workflow changes.
- Retained C/furcina silhouette, regenerated green site/app/native icon consumers.
  Tray stays monochrome and byte-identical. No dependency or schema changes.
- Updated public implemented/planned claims, all generation prompts/provenance,
  SITE/UI/PLAN, README and AGENTS. No new policy/grants or durable events are needed
  for this presentation-only slice.

Verification:
- `rtk proxy python3 bin/check-site`: passed, 35 links/assets plus accessibility,
  provenance, four scenes/seven foreground instances and Pages publishing boundary.
- `rtk proxy node --test test/site_test.mjs`: 4 passed, bounded scroll/coalescing,
  independent layers, pause/reload, OS reduced-motion changes and denied storage.
- `rtk mix quality`: 179 passed; format/compile/Credo/Sobelow/audit passed. Existing
  Sobelow quoted-keyword warnings while parsing Mix.lock remain; no vulnerabilities.
- `rtk proxy bin/brand-icons`, repeated under a Python hash assertion: all six
  consumers identical on repeat. System Python lacks Pillow; bundled Python used
  for read-only alpha checks (29.3–81.0% transparent/near-transparent) and contrast
  checks (body/muted/action text 8.87:1 or higher). Pixels were not edited.
- `rtk proxy bin/dev.build`: passed; normal dylib relocation/re-sign diagnostics.
- `rtk proxy bin/smoke`: passed native bootstrap/session/origin/replay/heartbeat,
  protected routes, graceful quit/listener cleanup. Data: `/private/tmp/ccoding-smoke.P6aA0F`.
- CUA browser at 1440×1000 and 390×844: inspected hero, roles, crossed duel,
  Pan/robot party and melancholy finale. No horizontal page overflow; keyboard
  board scrolling works. Pause stopped all eleven layers and survived reload;
  resumed before handoff. Narrow weapon placement refined after visual inspection.
  Screenshots: `/private/tmp/cuckoding-r018-visual/site-desktop.png` and `site-mobile.png`.
- Reduced-motion behavior tested in Node and CSS inspected; no-JS fallback checked
  structurally. OS-toggle/browser-no-JS manual runs were not performed.
- `rtk proxy git diff --check`: passed after trimming an extra artwork-doc newline.
  Python relative-link check passed 110 references in changed docs/task/worklog.

Running app: `/private/tmp/cuckoding-r018-proof-dl0b0pzi/Cuckoding.app`, native
SHA-256 `56a0063cbf72f40286de5d1ce03c91b2861f035e5a4d3f211375e8131ddaf7e0`.
Owned shell PID 42617, BEAM 42624, loopback port 57377. Exact start identities are
retained in `proof.json`. No active commands preceded restart. Prior proof's stop
script verified executable/parent/start identities and graceful service/shell/
listener cleanup. New native handshake reused `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data`.
Running CSS bytes match the packaged asset and contain the new palette. Retained
test launchers point to this artifact. Static preview runs on loopback 4387.

App visual QA remains unverified: native browser control was interrupted while
Chrome was in use; the in-app browser blocks the authenticated app port. No user
browser settings were changed. Rust tests, provider inference, migrations,
sleep/wake and clean-machine release gates were not repeated for a CSS/asset change.
No push, deployment or signed/notarized release. Local main integration follows
these checks; old artwork remains recoverable from parent commit 738f8ee.
