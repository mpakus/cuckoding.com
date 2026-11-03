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

## Autonomous office gallery — 2026-11-02

Three additional original illustrations were generated with the built-in Imagegen
tool for this request, with no external reference images or copied artwork.
The generated PNG sources remain in the conversation's Imagegen output.
Project-consumed WebP files are committed in site/assets, encoded with cwebp:
full 1536×1024 at quality 80, small 768×512 at quality 78. Only encoding and
resolution changed; the image content was not composited or retouched.

- escalation-committee.webp and escalation-committee-small.webp: three robot
  executives inspect a tiny bug while a human serves coffee.
- human-in-the-loop.webp and human-in-the-loop-small.webp: an office worker
  stamps paperwork inside a literal brass loop while a robot supervises.
- quarterly-results.webp and quarterly-results-small.webp: the robot receives
  the trophy while humans applaud and connect its charger.

The additional gallery remains fictional satire. Product copy now distinguishes
ordinary supervised integration from an explicitly started Autopilot, describes
model escalation and preserved checks, and keeps release/provider limits honest.
Published commit `5a6d15c9073fa615fd0d67788316f31ea8eec8e3` contains only
site markup/styles, six new WebP files and this documentation relative to freshly
fetched remote main. [Pages run 41579508007](https://github.com/mpakus/cuckoding.com/actions/runs/41579508007)
passed check and deploy. All 19 public resources match committed bytes over
verified HTTPS. Local browser checks covered 320/768/1024/1440 px, the new
second-opinion step, loaded artwork and Pause motion. The live browser also
confirmed the new gallery. The lower two images remain uncropped 3:2 stills;
only the committee image shares the existing bounded parallax.

### escalation-committee generation prompt

Use case: ads-marketing. Create an ORIGINAL luxury editorial satirical photograph for the Cuckoding AI coding website. Landscape 1536x1024. Scene: three polished retro-futurist chrome humanoid robots in an absurdly elegant Mediterranean executive meeting room, seated around a round pale travertine conference table. One robot solemnly uses a large magnifying glass to inspect a tiny red toy bug on an open laptop, another gestures grandly at blank sheets, the third reclines with a tiny espresso. A quietly exhausted adult human office worker in an ivory shirt and loosened tie stands beside the table holding a silver coffee tray. The machines have escalated a tiny problem into an expensive management committee; the human serves coffee. Make the visual joke instantly legible and dry, not cartoonish. Warm cream and peach plaster architecture, sage green upholstery, sunlight, real chrome reflections and linen texture, subtle analog film grain, sophisticated magazine art direction. Balanced wide composition, people, robots, tiny bug and table inside central 80 percent for responsive crops. No text, no logos, no watermarks, no real people, no violence, no sexual elements. Match the visual world of a chrome robot vacationing at a Mediterranean resort while humans do the work.

### human-in-the-loop generation prompt

Use case: ads-marketing. Create an ORIGINAL satirical luxury editorial photograph for Cuckoding, about AI and humans. Landscape 1536x1024. In a beautiful minimal Mediterranean office with pale peach plaster, warm ivory floor and sage details, an adult human office worker in an ivory shirt and loosened tie sits at a small desk INSIDE a huge upright circular brass ring, like an elegant oversized free-standing hoop surrounding the worker and desk. The ring is a harmless decorative frame, not a restraint or cage. The worker dutifully stamps blank cream paperwork with an oversized dark green rubber stamp, looking politely resigned. Outside the ring a sleek chrome humanoid robot in a relaxed executive pose hands a tall neat stack of papers through one side and collects approved papers from the other side with its other hand. Visual pun: the human is literally in the loop, reduced to approval bureaucracy while the machine manages everything. The ring must be a clearly visible complete circle, the human's face and stamping hand easily legible, the robot unmistakably in control. Warm editorial sunlight, tactile paper and linen, believable chrome reflections, fine analog grain, elegant sophisticated absurdism. Wide composition with ring and both characters comfortably inside central 80 percent, no crops of heads. No written words, no logos, no watermark, no real public figures, no chains, no violence, no fetish or sexual content.

### quarterly-results generation prompt

Use case: ads-marketing. Create an ORIGINAL sarcastic luxury editorial photograph for Cuckoding, a website about humans serving AI. Landscape 1536x1024. Scene: an elegant small corporate award ceremony on a sunlit Mediterranean terrace, pale peach arches and cream stone with sage-green details. A beautifully polished chrome humanoid robot stands proudly on a low stage holding a lavish gold trophy shaped like an abstract computer chip. Beside it, an adult tired human software engineer in a slightly crumpled ivory shirt and loose tie is on one knee adjusting a clearly visible charging plug connected to the robot's ankle. Three other adult human office workers stand nearby offering dutiful unenthusiastic applause, one holding a large cardboard box full of power adapters. The robot gets all the credit; the humans supply all the work. Dry corporate irony, refined and funny, not threatening or cruel. Robot and charging human are primary and large in frame; the cable and trophy should make the contrast instantly readable. Beautiful photographic chrome, gold, linen and stone materials, warm late-afternoon shadows, subtle film grain, high-end editorial art direction consistent with a chrome-robot Mediterranean resort shoot. Keep all key characters inside central 80 percent for narrow responsive framing. No text, no logos, no watermark, no real public figures, no violence or sexual elements.
