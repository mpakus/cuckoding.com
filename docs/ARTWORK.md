# Layered Roman satire

R017 assets generated with the built-in imagegen tool on 2026-10-07. Each scene
uses an independent opaque background and two transparent foreground PNGs.
All eight character images have real alpha (44–72% transparent or near-transparent pixels).
The original generated pixels are retained; CSS alone composes and moves them.
No asset is a product screenshot, historical depiction or evidence of agent support.

| Scene | Background | Foregrounds |
| --- | --- | --- |
| Arena duel | arena-back.png | gladiator-sword.png, gladiator-morgenstern.png |
| Banquet | terrace-back.png | banquet-robot.png, banquet-satyr.png |
| Pan's dance | arena-back.png | pan-dancer.png, robot-dancers.png |
| Melancholy finale | doom-back.png | robot-emperor.png, chained-humans.png |

Files live in `site/assets/`. The original R015 Colosseum remains only as the
static social preview. R016's flattened banquet/revels are replaced; source assets
and their exact prompts remain in Git history at `5d80ea4`. They supplied style
references, never new requirements. No third-party artwork was copied.

The original vector mark, `desktop/mark.svg`, is a cheeky C with horns, a wink
and one curling sperm/devil tail ending in a two-pronged furcina. It is authored
as SVG, then exported with `bin/brand-icons`; it is not an AI raster trace.

## Final image-generation prompts

### arena-back.png

Reference: R015/R016 `colosseum.png`. Transparent background: no.

Use case: precise-object-edit. Create a 1536x1024 BACKGROUND PLATE from the reference. Keep the immense Roman Colosseum, curved ranks of arches, distant cheering spectators, red awnings and banners. Remove ALL foreground robots, foreground spectators, furniture and Emperor: the entire lower 60 percent must be clear sunlit sandy arena floor, extending to the bottom edge, ready to composite separate large gladiators. Eye-level low arena camera, level horizon around top third. No hero figures, no weapons. Match the reference's fine ink linework and rich chalky gouache, vintage European illustrated Roman history-book plate, warm ivory limestone, charcoal olive shadows, vermilion cloth, muted bronze. Satirical concept illustration, no text, logos or watermark.

### terrace-back.png

Reference: R015/R016 `robot-banquet.png`. Transparent background: no.

Use case: precise-object-edit. Create a 1536x1024 BACKGROUND PLATE from reference. Preserve Roman terrace architecture, left columns, red curtains, ivy, distant Colosseum and warm afternoon light. Remove ALL people, robots, satyrs, foreground couches, tables and food. Lower half is empty elegant limestone terrace floor extending to bottom, ready for separate characters and couches. Match the reference's fine ink linework and rich chalky gouache, vintage European illustrated Roman history-book plate, warm ivory limestone, charcoal olive shadows, vermilion cloth, muted bronze. Satirical concept illustration, no text, logos or watermark.

### doom-back.png

Reference: R015/R016 `colosseum.png`. Transparent background: no.

Use case: illustration-story. Create a 1536x1024 BACKGROUND PLATE for a melancholy satirical final Roman scene. Same vast Colosseum, now evening after the festivities. Empty arena floor in foreground, deserted tiers, slumped red banners, fading braziers, atmospheric leaden blue-grey sky with thin cold sunset. Distant luxurious imperial balcony lit with warm gold suggesting a party just out of view. Lower half completely clear to composite separate characters. No people or robots in this background plate. Match the reference's fine ink linework and rich chalky gouache, vintage European illustrated Roman history-book plate, warm ivory limestone, charcoal olive shadows, vermilion cloth, muted bronze. Satirical concept illustration, no text, logos or watermark.

### gladiator-sword.png

Reference: R015/R016 `colosseum.png`. Transparent background: yes.

Use case: illustration-story. A single isolated robot-gladiator SPRITE on REAL transparent background, square 1024x1024. Based on the reference's bronze monitor-faced robot, broad comical Roman armor, little vermilion cape, absurdly confident smiling screen-face. FULL BODY boots to helmet entirely visible, no floor, no background, no additional figures. Faces RIGHT, lunging in from the LEFT. Holds a long straight steel gladiator sword with BOTH HANDS: hands near lower-center of sprite, blade extends diagonally UP and RIGHT to upper-right region. Blade must be clear and straight, reaching far ahead of robot; its tip fully inside canvas. This will cross another opponent's mace diagonally at the center of a webpage. Robot body predominantly in left half, weapon occupies right half, all bounds within image and only a slim transparent margin. No shields blocking sword. Match the reference's fine ink linework and rich chalky gouache, vintage European illustrated Roman history-book plate, warm ivory limestone, charcoal olive shadows, vermilion cloth, muted bronze. Satirical concept illustration, no text, logos or watermark.

### gladiator-morgenstern.png

Reference: R015/R016 `colosseum.png`. Transparent background: yes.

Use case: illustration-story. A single isolated robot-gladiator SPRITE on REAL transparent background, square 1024x1024. Based on the reference's ivory crested robot, red Roman plume, expressive annoyed black faceplate, elegant mechanical Roman armor and little vermilion cape. FULL BODY boots to plume entirely visible, no floor/background/additional figures. Faces LEFT, lunging in from the RIGHT. Holds a MORGENSTERN: a long rigid dark shaft with a bronze spiked ball at its end (a morningstar mace, not a flail). Hands near lower-center, shaft extends diagonally UP and LEFT to upper-left region, entire spiked ball within canvas. It must be positioned to cross another opponent's straight sword when moving together. Robot body predominantly in right half, weapon occupies left half, only a slim transparent margin. Funny theatrical non-gory combat. Match the reference's fine ink linework and rich chalky gouache, vintage European illustrated Roman history-book plate, warm ivory limestone, charcoal olive shadows, vermilion cloth, muted bronze. Satirical concept illustration, no text, logos or watermark.

### banquet-robot.png

Reference: R015/R016 `robot-banquet.png`. Transparent background: yes.

Use case: illustration-story. Transparent-background foreground cutout, landscape square-ish sprite. ONE absurdly happy bronze monitor-faced robot in a laurel wreath, reclining on a red Roman chaise longue with gold feet. Robot tilts its goblet toward its smiling open faceplate as if drinking wine and dangles a big bunch of grapes over its head; wearing little imperial cape. Include couch, one bowl of grapes at feet, no floor or backdrop or other figures. Face turned slightly right, relaxed funny pose. This sprite will float above an independently scrolling Roman terrace. Same sophisticated hand-painted vintage European editorial plate as reference: fine ink linework, rich chalky gouache, subtle printing texture, ivory, warm bronze, charcoal olive and vermilion, precise expressive faces. No text or logos, no watermark. Full subjects and all props inside canvas with small clear margin. Satirical non-gory concept art. All humans/satyrs are adults, clothed.

### banquet-satyr.png

Reference: R015/R016 `robot-banquet.png`. Transparent background: yes.

Use case: illustration-story. Transparent-background foreground cutout. ONE jovial ADULT satyr with beard, little horns and goat legs, in a modest linen tunic, raising a goblet in a toast and laughing. He sits next to ONE scrappy dark steel robot playing a little lyre with exaggerated passion, head tilted back. Include their two low Roman stools, no architecture, no other people, no floor. This is a separate foreground sprite in a robot banquet. Full bodies and feet visible. Same sophisticated hand-painted vintage European editorial plate as reference: fine ink linework, rich chalky gouache, subtle printing texture, ivory, warm bronze, charcoal olive and vermilion, precise expressive faces. No text or logos, no watermark. Full subjects and all props inside canvas with small clear margin. Satirical non-gory concept art. All humans/satyrs are adults, clothed.

### pan-dancer.png

Reference: R015/R016 `pan-revels.png`. Transparent background: yes.

Use case: illustration-story. Single foreground character cutout on REAL transparent background. Jovial ADULT Pan with curved horns, full beard and goat legs, wearing a modest short linen tunic. Plays panpipes with cheeks puffed, one knee raised high in a ridiculous joyful dancing step, body leaning slightly toward RIGHT. Complete figure horns to both hooves with room around limbs, no floor, no other subjects, no backdrop. Same sophisticated hand-painted vintage European editorial plate as reference: fine ink linework, rich chalky gouache, subtle printing texture, ivory, warm bronze, charcoal olive and vermilion, precise expressive faces. No text or logos, no watermark. Full subjects and all props inside canvas with small clear margin. Satirical non-gory concept art. All humans/satyrs are adults, clothed.

### robot-dancers.png

Reference: R015/R016 `pan-revels.png`. Transparent background: yes.

Use case: illustration-story. Foreground cutout on REAL transparent background. Two deliriously happy Roman robot gladiators dance together: one bronze monitor-faced robot and one ivory crested robot, holding hands, one stepping high while the other bows theatrically. Red cloth fluttering, clear silly poses, metal knees raised, joyful face displays, facing toward LEFT a little. Full bodies with all feet and crests visible. No floor, background or additional figures. Same sophisticated hand-painted vintage European editorial plate as reference: fine ink linework, rich chalky gouache, subtle printing texture, ivory, warm bronze, charcoal olive and vermilion, precise expressive faces. No text or logos, no watermark. Full subjects and all props inside canvas with small clear margin. Satirical non-gory concept art. All humans/satyrs are adults, clothed.

### chained-humans.png

Reference: R015/R016 `robot-banquet.png`. Transparent background: yes.

Use case: illustration-story. Wide foreground cutout on REAL transparent background. Darkly satirical, melancholy illustration of THREE ordinary ADULT Roman people who have outsourced all pleasure to robots. A tired man sits on a low stone head in hands; an exhausted woman stares sadly ahead with slack shoulders; a third weary adult stoops under a huge stone sphere chained to their wrists. All wear plain modest worn tunics. Heavy exaggerated iron chains connect their wrists and ankle shackles to three absurd stone weights; symbolic weight of doom, no writing. Bodies and expressive sad faces dignified, not caricatures of any race. A dropped theatrical comedy mask and wilted laurel on ground next to their feet. Complete figures, chains and weights fully visible; no architecture or painted ground, just transparent cutout. No gore, injury, nudity, torturer, sexual context or children. Cooler muted limestone/grey/olive tones, unlike the warm happy robots. Same sophisticated hand-painted vintage European editorial plate as reference: fine ink linework, rich chalky gouache, subtle printing texture, ivory, warm bronze, charcoal olive and vermilion, precise expressive faces. No text or logos, no watermark. Full subjects and all props inside canvas with small clear margin. Satirical non-gory concept art. All humans/satyrs are adults, clothed.

### robot-emperor.png

Reference: R015/R016 `robot-banquet.png`. Transparent background: yes.

Use case: illustration-story. Separate foreground cutout on REAL transparent background. TWO hilariously complacent robots have inherited humanity's leisure: a bronze monitor-faced robot Emperor lounges on a luxurious Roman couch in purple and vermilion robes and a golden laurel crown, smiling smugly, raising a goblet; an ivory robot companion reclines beside it, dangling grapes above its own delighted face. Include rich red/gold couch, small platter of grapes, no floor, no architecture, no humans or other figures. FULL couch and figures visible. Warm golden light on polished bronze. This will contrast with a separate foreground group of sad shackled Roman humans in the final scene. Same sophisticated hand-painted vintage European editorial plate as reference: fine ink linework, rich chalky gouache, subtle printing texture, ivory, warm bronze, charcoal olive and vermilion, precise expressive faces. No text or logos, no watermark. Full subjects and all props inside canvas with small clear margin. Satirical non-gory concept art. All humans/satyrs are adults, clothed.
