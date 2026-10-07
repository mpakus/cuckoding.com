# Public site — cuckoding.com

`site/` is the complete GitHub Pages document root. It is native HTML/CSS/JS,
independent of the Phoenix app and Tauri bundle. No build, package installation,
third-party fonts, analytics or client-side routing is required.

## Design and content

The site is a satirical Roman playbill: parchment, dark ink, vermilion, system
serif headings, robot gladiators and a hungry, angry, laughing crowd. The image
is explicitly concept art; the sample Tabula is explicitly illustrative.

Three illustrated scenes move on scroll: combat, the robot banquet, and Pan’s
arena revels. Foreground stamps move in the opposite direction for depth; text
stays still. Movement is bounded within each image’s overscan. The fixed native button pauses/resumes all parallax and remembers the
choice when storage is available. OS reduced motion takes precedence, including
changes while the page is open. Denied storage is harmless. Without JavaScript,
the complete site, anchors and board remain usable and the motion control is hidden.
The board can be scrolled by keyboard and touch; no drag interaction is required.

The status section mirrors R010: local shell/browser, durable storage and tool
detection. Provider authorization, models, roles, boards and autonomous battles
are planned. Ten-minute setup is an ambition, not measured acceptance. There is
no download CTA or claim of a signed/notarized release. Keep those boundaries
current when future implementation is integrated.

## Preview and checks

From the repository root:

```sh
rtk proxy python3 -m http.server 4387 --bind 127.0.0.1 --directory site
rtk proxy python3 bin/check-site
rtk proxy node --test test/site_test.mjs
rtk git diff --check
```

Open `http://127.0.0.1:4387/`. Check desktop and narrow views, all section links,
horizontal board scrolling, visible keyboard focus, parallax/pause/reload, and
reduced motion. The structural check validates published assets, local anchors,
scope/provenance labels and workflow boundary. The Node tests exercise bounded
motion, frame coalescing, pause persistence, system preference changes and denied
storage without adding a browser-testing dependency.

## GitHub Pages deployment

`.github/workflows/pages.yml` checks pull requests and relevant pushes; only
`main` can deploy, after checks pass. The artifact contains only `site/`. Official
actions are pinned to verified commit hashes. The deploy job alone gets Pages
and identity-token write permissions. Local merging does not publish the site.

When publication is explicitly requested, push the reviewed main revision and
select **GitHub Actions** in the repository's Pages publishing settings. Configure
the custom domain `cuckoding.com` in Pages, verify its DNS and enable HTTPS once
GitHub provisions the certificate. The committed CNAME/canonical/robots/sitemap
express the intended domain; they do not establish current DNS or deployment.
Assets use relative paths and also work below a project Pages prefix.

Source: [GitHub's custom Pages workflow documentation](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).
Motion APIs: [matchMedia](https://developer.mozilla.org/en-US/docs/Web/API/Window/matchMedia)
and [prefers-reduced-motion](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@media/prefers-reduced-motion).
No third-party application implementation was copied.

## Artwork provenance

`site/assets/colosseum.png` was generated with the built-in imagegen tool on
2026-10-06 for this request. It is 1536×1024, retained without editing; CSS crops
the view responsively. It is not a screenshot, historical depiction or evidence
of runtime support. The logo is an original trident with code brackets: three agent prongs join one
coordinated stem. `desktop/mark.svg` is the source. Run `rtk proxy bin/brand-icons`
to regenerate the site mark, both favicons, native PNG/ICNS and monochrome tray
mask. ICNS chunks are sorted for reproducible exports.

The two additional scenes and their final prompts are in [Artwork](ARTWORK.md).

Original hero image-generation prompt:

> Use case: illustration-story. Asset type: ultra-wide editorial hero artwork for the Cuckoding.com website, about AI coding agents staged as an absurd ancient Roman gladiator spectacle. Create one richly detailed panoramic illustration, landscape 3:2 or wider. A HUGE recognizable ancient Roman Colosseum seen from within the stands, full of thousands of spectators, dramatic tiered stone arches and striped red awnings. In the sandy central arena, three distinct large retro-futuristic robot gladiators fight a theatrical, non-gory battle: a bulky bronze robot with a squared monitor face and oversized keyboard shield, a sleek ivory robot with red crest and a stylus spear, a scrappy dark steel robot tangled in a scroll of code. Funny physical poses and flying harmless papers; no injury or blood. In the close foreground, expressive diverse adult Roman spectators in tunics and togas: hungry people chewing bread and olives, angry people waving thumbs down, laughing people cheering wildly, a bored noble reviewing a wax tablet. Their human faces are readable, lively, individual, affectionate satire, not frightening. Art direction: sophisticated hand-painted vintage European editorial / illustrated Roman history-book plate with fine ink linework, rich chalky gouache, subtle printed-paper texture, warm ivory and sunlit limestone, deep charcoal olive shadows, terracotta vermilion accents, softly muted bronze metals. Cinematic depth, noon sunlight and a little dusty atmosphere, elegant coherent forms, spectacular sense of scale. Keep all meaningful subjects within the frame, clear central focus on the robots. No text, lettering, UI, logos, watermark, photorealism, neon cyberpunk, modern billboards, blurry faces, or blood. This is satirical concept art, not a product screenshot.
