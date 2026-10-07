# Public site — cuckoding.com

`site/` is the complete GitHub Pages document root. It is native HTML/CSS/JS,
independent of the Phoenix app and Tauri bundle. No build, package installation,
third-party fonts, analytics or client-side routing is required.

## Design and content

The site is a satirical Roman playbill: parchment, dark ink, vermilion, system
serif headings, robot gladiators and a hungry, angry, laughing crowd. The image
is explicitly concept art; the sample Tabula is explicitly illustrative.

Four scenes each combine a background with two independent transparent character
images: the scroll-driven sword/morgenstern clash, the drinking robot and satyr
musicians, Pan and dancing robots, then chained melancholy people beneath robot
leisure. The duel stays in view while the weapons approach and cross. Other
characters bob, tilt or sink with scroll position; text stays still. The same
Arena backdrop returns for the afterparty, with a quieter color treatment.

Transforms are bounded, use one coalesced animation frame per scroll/resize, and
never run an idle animation loop. The fixed native button pauses/resumes every
layer and remembers the choice when storage is available. OS reduced motion takes
precedence, including changes while open. Denied storage is harmless. Without
JavaScript, all scenes, anchors and the keyboard-scrollable board remain usable;
the hidden motion control does not advertise an unavailable action.

The status section mirrors R010/R020a: local shell/browser, durable storage, tool
detection and explicitly consented Codex version checks. Provider authorization, models, roles, boards and autonomous battles
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

The full display name is **Cuckoding**, abbreviated **CC**. **Emperor** is always
capitalized in public copy. The icon is a playful C whose curling sperm/devil tail
ends in a furcina. `desktop/mark.svg` is the source; run `rtk proxy bin/brand-icons`
to regenerate the site mark, both favicons, native PNG/ICNS and monochrome tray.
ICNS chunks are sorted for reproducible exports. Display renaming does not migrate
private data paths or alter internal protocol/environment identifiers.

[Artwork](ARTWORK.md) records the layer map, original prompts and provenance.
The old flattened Colosseum illustration remains only in social metadata, where
a static preview is required; all four visible scenes are separate image layers.
