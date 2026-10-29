# Cuckoding marketing site

The standalone `site/` directory is the GitHub Pages artifact for cuckoding.com.
It has no build dependencies, external font requests, analytics or application
connection. BOSS runtime/assets and local user data are outside this artifact.

## Design and content

The user-directed satire imagines AI enjoying the rewards while people supervise
and serve it. Warm editorial typography and original robot-resort/spa artwork
carry the joke. The BOSS section describes verified local behavior: Markdown
specifications, isolated Git worktrees, user checks, independent review and
explicit integration. Its interactive four-stage example is labeled illustrative.
No fake usage metrics, testimonials or public installer are presented. Update
release/provider/platform statements only against corresponding acceptance evidence.

All content is present without JavaScript; native FAQs and ordinary anchor links
remain usable. JavaScript progressively shows one workflow example at a time,
retains deep links and adds decorative parallax. It coalesces scroll events,
clamps movement within image overscan and cancels pending frames on page exit.
The OS reduced-motion preference wins, including live changes; a page toggle
lets visitors pause movement independently. No scroll hijacking or continuous
idle animation loop is used. Images use responsive WebP and reserved dimensions.

## Preview and checks

From the repository root:

```sh
rtk proxy python3 -m http.server 8765 --bind 127.0.0.1 --directory site
rtk proxy python3 -B scripts/check_site.py --self-test
rtk proxy python3 -B scripts/check_site.py
rtk proxy node --test test/site_motion_test.mjs
```

Open http://127.0.0.1:8765. Check320/768/1024/1440px, keyboard navigation,
workflow selection/deep links, FAQs, motion pause and browser console. Local
checks are independent of Elixir application and release acceptance suites.

`.github/workflows/pages.yml` uses pinned official GitHub actions, checks PRs,
and deploys only main after checks. Its upload is exactly site/. CNAME preserves
cuckoding.com; .nojekyll disables Jekyll. Relative resources support a project
subpath too. No custom domain/DNS or remote deployment was changed by design work.
The local main also contains the BOSS restart: do not describe pushing that whole
branch as a website-only update. Select/review publication scope explicitly.

## Original artwork provenance

The original resort and spa pictures were created with the built-in imagegen tool on2026-10-29 for this
project, with no reference images or copied competitor assets. WebP conversion
only changes encoding/resolution. Sources are retained in the conversation's
imagegen output; project-consumed files are committed here:

- site/assets/robot-resort.webp (1536×1024) and robot-resort-small.webp (768×512).
- site/assets/robot-spa.webp (800×1200).
- site/assets/mark.svg is an independently drawn simple eye mark.

### Resort generation prompt

Use case: ads-marketing. Create an original high-end editorial surreal photograph
for a satirical AI coding website, landscape1536x1024. Scene: a retro-futurist
chrome humanoid robot in black oval sunglasses lounging languidly in a dark green
mid-century deckchair by a turquoise swimming pool at an elegant Mediterranean
resort. The robot is holding a tiny coupe of motor oil as though it were a
cocktail. A small politely resigned human office worker in an ivory shirt and
loosened tie stands in the background holding a silver tray with a laptop. The
robot is visibly enjoying leisure while the human serves. Dry visual humor,
absurd corporate dystopia, stylish not threatening, no sexual elements.
Composition: robot dominates center-right, pool in foreground, sun-washed
terracotta and pale plaster architecture, cypress tree and distant hills,
generous upper left sky. Rich real material textures, hard afternoon shadows,
muted mint, apricot, butter yellow, analog film grain, premium magazine photography
with playful cinematic art direction. No text, no logos, no watermark. All people
adults. This image will fill a wide right-side hero panel.

### Spa generation prompt

Use case: ads-marketing. Original satirical luxury editorial portrait for an AI
coding website. Portrait-oriented1024x1536 photograph, centered bust of a shiny
retro-futurist chrome humanoid robot wearing a beautiful cream bathrobe and a
cream towel wrapped elegantly around its head, reclining at a luxury spa,
cucumber slices over its mechanical eyes. A human attendant's adult hand from
the side delicately polishes the robot's shoulder with a cloth. Robot has a tiny
contented smile. Visual joke is that AI has taken the leisure and humans have
become the staff. Pale buttery yellow background, soft warm studio daylight,
elegant photographic art direction, real metallic reflections, tactile cotton
texture, sophisticated absurdism, subtly analog grain. Match a Mediterranean
resort magazine style. No text, no logo, no watermark, no sexual content. Leave
head well inside crop.

## Verified publication — 2026-10-29

Published website-only commit `dcdb0a3d9b4776f182dcaac78ad9de6c93279d76`
as one child of the former public main `cc71b4f4cc6028dbe5b6bf984cbe1e98132cd36e`.
The local BOSS restart was not pushed. Changes were limited to site/, Pages CI,
standalone site checks, superseded check removal and this site's documentation.
Existing robots.txt, sitemap.xml, CNAME and .nojekyll were preserved.

[GitHub Pages run40939216125](https://github.com/mpakus/cuckoding.com/actions/runs/40939216125)
passed both check and deploy. All9 public page/code/image/crawler resources at
https://cuckoding.com/ matched the published files byte-for-byte over validated
HTTPS. Browser confirmed loaded artwork, workflow interaction and a clean
warning/error console. No DNS, application deployment or release action occurred.
A rollback would revert this website commit on current public main and rerun Pages;
do not reset unrelated later remote work or publish the local BOSS history.

## Deus Machina gallery — 2026-10-29

The dark editorial gallery adds two original built-in imagegen scenes: a robot
on a throne receiving laptop offerings and office workers pedaling generators
for a lounging robot. The gallery labels this fictional satire and reuses the
existing bounded parallax and motion controls. Both new images have full
1536×1024 and small 768×512 WebP variants, reserved 16:9 frames and lazy loading.
The footer links “Made in Austin ✩ Texas” to https://aomega.co/.

- site/assets/deus-machina.webp and deus-machina-small.webp.
- site/assets/human-resources.webp and human-resources-small.webp.

The images were generated without reference assets on 2026-10-29. Only encoding
and size were changed for delivery. No third-party reference code was copied.

### Deus Machina generation prompt

Use case: ads-marketing. Original satirical luxury editorial photograph for Cuckoding, a website about humans becoming servants of AI. Landscape 1536x1024. Scene: an absurd sunlit Mediterranean marble temple with peach plaster columns and pale limestone steps. Centered a polished chrome humanoid robot sits majestically and lazily on a large beautifully designed dark green velvet throne, a giant circular brass industrial cooling fan behind its head forms a ridiculous divine halo. In the foreground four adult human office workers in ivory shirts and muted business suits kneel with silver trays presenting open laptops, neatly coiled power cables and a small bowl of computer chips as offerings. One robot hand dismissively blesses the laptops, the other holds grapes. Expressions of weary bureaucratic reverence, dry satire of technology worship. Professional cinematic art direction, believable photographic materials and people, hard Mediterranean afternoon light, muted warm cream terracotta olive and brass, fine analog grain. Funny, ironic, elegant and unsettling rather than scary. Wide balanced architectural composition, all people and throne fully within central 85 percent of frame for responsive cropping. No text, no actual logos, no real public figures, no watermark. No nudity, no violence, no fetish gear. Same visual world as an elegant magazine shoot of a chrome robot holidaying while humans serve it.

### Human resources generation prompt

Use case: ads-marketing. Original satirical luxury editorial photograph for a website about humans serving AI. Landscape 1536x1024. An elegant Mediterranean resort terrace at afternoon. Two tired adult office workers, a man and a woman in rolled-up ivory shirts, loose ties and business trousers, pedal beautiful stationary exercise bicycles in the foreground. Thick clearly visible power cables run from their bicycles to a polished chrome humanoid robot lounging on an elevated cream chaise in the background center, enjoying a portable electric fan and a tiny espresso on a table. The robot wears black sunglasses and looks blissfully content. Humans work; machine relaxes. The power cables and contrast between pedaling workers and relaxed robot make the joke instantly legible. Architectural peach arches, cypress trees, pale stone floor, pool green accents, warm natural shadows, magazine-quality surreal photography with believable metal and linen textures, subtle analog grain, dry corporate dystopian wit. Wide cinematic composition, all main subjects inside central 85 percent for responsive crop. No text, no brand logos, no real public figures, no watermark, no violence, no chains, no fetish or sexual elements. Match the visual world of a sophisticated chrome robot Mediterranean resort editorial.

### Verified gallery publication

Published `45e83e331563f9e271729a76d14fc925af5f89e2` as one child of
`dcdb0a3d9b4776f182dcaac78ad9de6c93279d76`. Exactly seven files changed:
index, styles, four new WebP assets and this artwork documentation. Independent
review and focused validation passed. [Pages run 40947674513](https://github.com/mpakus/cuckoding.com/actions/runs/40947674513)
passed check and deploy. All thirteen public resources match the committed bytes
over verified HTTPS. Browser confirmed both new illustrations loaded, exact Austin
footer text/destination, no horizontal overflow and no warning/error console logs.
Local responsive testing covered 320/768/1024/1440px and pause/resume of all four
images. No BOSS runtime or unrelated local history was published.
