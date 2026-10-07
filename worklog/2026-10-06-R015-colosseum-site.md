# R015 — Coliseum public site

Status: complete, verified for local main integration on `feature/r015-colosseum-site` after R010 local merge `86ef4b3`.
Acceptance: [task](../tasks/R015-colosseum-site.md).

## Approach and sources

- User requests static `site/` for GitHub Pages, ancient Roman irony, robot fights,
  expressive spectators, scrolling and parallax. No external publication requested.
- Read current product/flow/UI/plan contracts. Apply Ponytail full 4.13.0 (MIT),
  quality-gates, imagegen, better-ui, animate and typography guidance.
- Existing app is LiveView; public site has no implementation to reuse after reset.
  Use native HTML/CSS and small progressive-enhancement JS, no site framework.
- RTK proxy exceptions: exact Python/Node scripts, generated artwork copy and
  loopback preview need unfiltered/protocol output. All shell entries use RTK.
- Local reference index has no current site peer. Adapt no third-party source;
  use official GitHub Pages workflow and browser-native media/animation APIs.
- GitHub Actions refs verified from official repositories with `rtk git ls-remote`:
  checkout v6 `d23441a48e516b6c34aea4fa41551a30e30af803`, configure-pages v5
  `983d7736d9b0ae728b81ab479565c72886d7745b`, upload-pages-artifact v4
  `7b1f4a764d45c48632c6b24a0339c27f5614fb0b`, deploy-pages v4
  `d6db90164ac5ed86f2b6aed7e0febac5b3c0c03e`. Only the documented workflow interface is used; no action implementation is
  vendored or adapted.

## Implementation

- Native HTML/CSS and a small progressive-enhancement script; no framework,
  runtime dependency, external fonts, tracking or new plugin. Parchment/ink/red
  playbill, one original generated artwork, role descriptions, illustrative board
  and separate available/planned status. Saved the final generation prompt in
  [Site](../docs/SITE.md#artwork-provenance).
- OS reduced motion overrides parallax; a native pause control persists choice
  where storage is allowed. No hidden content/reveal dependency, no continuous
  animation loop. Focusable board uses native horizontal keyboard/touch scrolling.
- Pinned Pages actions publish only `site/`, after checks, from main; PR checks
  have no deployment authority. CNAME/metadata target cuckoding.com without
  claiming existing DNS or publication. README, AGENTS, plan and testing updated.
- Original/copied PNG SHA-256 both match:
  `678313b54c4e15d76c3653b59ecfa05b6d820e9fc0edb13d1bd00685ffa94edc`.
- Primary references: [official Pages workflow](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages),
  [matchMedia](https://developer.mozilla.org/en-US/docs/Web/API/Window/matchMedia)
  and [reduced motion](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@media/prefers-reduced-motion).
  These establish the native interface; no peer code was copied.

## Verification

| Command / check | Result |
| --- | --- |
| `rtk proxy python3 bin/check-site` | Pass: 20 local/external references, local assets/anchors, accessibility structure, truthful scope/provenance labels, reduced-motion fallback, Pages artifact and pinned-action boundary |
| `rtk proxy node --test test/site_test.mjs` | 3 passed: bounded/coalesced movement; pause/reload and changing system preference; first-load reduced motion and denied storage |
| `rtk proxy node --check site/site.js` | Pass |
| `rtk proxy ruby -ryaml -e 'YAML.load_file(".github/workflows/pages.yml"); puts "PASS: Pages YAML parses"'` | Pass |
| Python Markdown local-link/anchor check | Pass: 38 documents (README, AGENTS, docs, tasks, worklogs, skills) |
| `rtk git diff --check` | Pass |
| `rtk proxy python3 -m http.server 4387 --bind 127.0.0.1 --directory site` + computer use | Actual rendered checks at 320, 390, 862 and 1440px; document width equals viewport in each case |
| Browser interactions | Section anchors, live parallax, pause/reload persistence and visible keyboard focus passed; ArrowRight moved the mobile board to scrollLeft 53; all five columns fit desktop |
| Browser diagnostics | No warning/error entries; hero loaded; responsive roles/status inspected |
| Source/structural no-JavaScript review | All content is serverless static HTML; motion button hidden until JS; links and native scroller need no JS. No separate browser-with-JS-disabled run claimed |

Browser testing caught missing whitespace around a line break hidden on mobile;
fixed it and reloaded the final source. Restored normal viewport and enabled
parallax for the delivered preview. Screenshot saved at
`/Users/mpak/.codex/visualizations/2026/10/07/01a11422-7a5a-7251-87cb-1d8f8b8e5fd4/ccoding-site-preview.jpg`.
Local preview remains at `http://127.0.0.1:4387/` for this session.

Actionlint is not installed; YAML parsing and the structural workflow check pass,
but no hosted Actions run, DNS check, HTTPS provisioning or Pages deployment is
claimed. Reduced-motion/storage failures are exercised in the Node harness;
no OS accessibility preference was changed. App source is unchanged by R015, so
its already-passing R010 suite/build was not rerun for this isolated static site.
No push/publication. Next application slice: R020, one real agent and model cache.
