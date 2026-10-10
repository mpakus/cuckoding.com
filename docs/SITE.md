# Public site — cuckoding.com

`site/` is the complete GitHub Pages document root. It is native HTML/CSS/JS,
independent of the Phoenix app and Tauri bundle. No build, package installation,
third-party fonts, analytics or client-side routing is required.

## Design and content

R018 replaces the parchment playbill with an original cybernetic Arena: near-black
`#050807`, electric green `#82ff52`, black chrome, orbital architecture and quiet
HUD framing. Bold system sans headings and monospace labels need no font network
requests. The Roman vocabulary and satire remain. The internal app shares the
palette, sharp panels, green focus/selection and navigation treatment, without
bringing cinematic decoration into forms.

R019 draws composition and scroll pacing from the user-requested
[1367 Studio](https://www.1367studio.com/) reference, visually inspected on
2026-10-10: a full-viewport portrait, scrolling camera approach, floating navigation
and spacious editorial sections. Its assets, code, copy and fonts are not reused.
Cuckoding uses original black/green emissary and orbital-vault artwork, oversized
background lettering, a full-width duel and staggered role portraits. Readable
copy and controls remain stationary within their sections.

Four scenes use independent layers: an emissary hero, a sticky sword/morgenstern
duel, cybernetic Pan and dancing robots, then chained melancholy humans beneath
robot leisure. Seven foreground instances use two background plates. Static role
cards reuse the earlier sentinel and gladiators. The hero is eager;
below-fold scenes/cards are lazy. Original PNGs are retained without pixel edits.
The artwork and board are explicitly illustrative, never evidence of shipped UI.

Transforms are bounded, use one coalesced animation frame per scroll/resize, and
never run an idle animation loop. A fixed native button pauses every layer and
remembers the choice when storage works. OS reduced motion takes precedence,
including live changes, and removes the extended sticky scenes. The camera scales
the emissary up to 1.42 and the vault up to 1.28, reversing directly with native
scrolling. Sticky distance is shorter on narrow screens. User pause resets every
layer without changing page height; extended sticky geometry is enabled only
after JavaScript initializes and the system allows motion. Without JavaScript,
content, anchors and the keyboard-scrollable board remain usable; the unavailable
motion control stays hidden. No flashing, autoplay, or animated text.

Status copy reflects implemented named Codex/Cursor connections, model selection,
Team bindings, Arenas/Tabulas/draft planning, and isolated worktree preparation and
inspection. Codex planning uses the scoped provider path; Cursor inference is not
enabled. Model listings do not prove access. Real-account acceptance, repository
execution, independent review, automatic task movement and autonomous battle
coordination remain open. Ten-minute setup is a target, not measured acceptance.
There is no public download claim or signed/notarized release claim.

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
motion, reversible bounded camera depth, stable pause geometry, frame coalescing,
pause persistence, system preference changes and denied
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
The current vault supplies the static social preview. Superseded painted assets
are retained in Git history, not shipped in the Pages directory.
