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

Both pictures were created with the built-in imagegen tool on2026-10-29 for this
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
