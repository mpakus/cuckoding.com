# Cybernetic Arena artwork

R018 originals generated with the built-in imagegen tool on 2026-10-10. The five
user-supplied images informed palette, material and composition only. No reference
pixels, watermarks, franchise characters or third-party artwork were copied.
R019 adds two originals on the same date: a black-chrome emissary with real alpha
and an opaque orbital vault. The requested [1367 Studio](https://www.1367studio.com/)
reference informed viewport composition and camera pacing only; none of its
assets or source were copied. All seven foreground assets have real alpha; both
backgrounds are opaque. R019a revises the emissary, vault, Pan and revelers with
the built-in image editor using only those existing original images as inputs.
The gothic direction uses fully clothed leather/harness stage fashion, ornamental
chains, spikes and cathedral architecture. Poses, dimensions and real foreground
alpha are preserved. Earlier versions remain in Git at `1b1f623`; the existing
filenames now serve the revised art in all scenes, including the finale's robots.
R019b revises `neon-arena.png` with more readable adult spectators in black leather,
ring harnesses, studded collars, cuffs and decorative chains. The architecture,
portal and empty floor remain the background for three independently layered scenes.
Tool-generated PNG outputs are retained without pixel post-processing and
composed/animated in CSS/JavaScript. These are
fictional satirical illustrations, not product screenshots or provider evidence.

| Scene | Background | Independent foregrounds |
| --- | --- | --- |
| Hero | neon-vault.png | neon-emissary.png |
| Duel | neon-arena.png | neon-duelist.png, neon-secutor.png |
| Afterparty | neon-arena.png | neon-pan.png, neon-revelers.png |
| Finale | neon-arena.png | neon-revelers.png, neon-humans.png |

Files live in `site/assets/`; static role-card crops reuse these originals. The
vault also supplies the social preview. Six foregrounds are reused in seven scene
instances, each covered by pause and reduced motion. Assets stay below 6 MB each;
only the hero loads eagerly. `neon-sentinel.png` remains in the Speculator portrait.
Prior Roman painted assets and exact prompts remain
recoverable in Git history before R018 (main `738f8ee`). Unused assets are removed
from the Pages payload.

`desktop/mark.svg` remains the original hand-authored C/furcina devil-tail logo.
R018 changes its accent to electric green and its icon tile to near-black, without
changing the silhouette. `bin/brand-icons` synchronizes site/app/native consumers
and normalizes ICNS chunk ordering for repeatable output.

## Arena spectator edit — R019b

Edited with built-in imagegen on 2026-10-10. Input: `site/assets/neon-arena.png`
at `462eb9d`; output replaces the same file. Opaque 1536×1024 PNG, no pixel
post-processing. The prior version remains in Git. Exact prompt:

Use case: precise-object-edit. Edit target: the supplied original site/assets/neon-arena.png. Keep this exact wide 1536x1024 black-and-electric-green orbital Colosseum background plate, centered emerald portal, planets, tiered stands, perspective, green grid reflections and completely EMPTY lower-half arena floor. Change the spectators' fashion: make the nearest adult crowd along the left and right LOWER STAND RAILINGS more readable, with varied expressive ADULT men and women wearing striking sci-fi gothic clubwear. Add opaque tailored black leather clothing under broad geometric chest harnesses, chrome O-ring hardware, buckled corset-style armor over shirts, studded chokers, spiked shoulder details, substantial wrist cuffs as fashion bracelets, decorative waist chains, and tall black boots. Some spectators cheer or lean over the rail, others fold their arms, keeping the playful gladiator-audience mood. Harnesses and chains are costume accessories only; nobody tied up. All people fully clothed, non-explicit fashion editorial: no nudity, exposed intimate body parts, sexual acts, erotic poses, suffering, weapons or children. Use green rimlight to reveal silver buckles and black leather. Keep people confined to existing spectator terraces, including the front row above the floor; no people or new props in the central foreground, do not obscure the portal. Preserve the architecture and composition as closely as possible. Black, charcoal, silver chrome and acid-green only. Original cinematic sci-fi concept art, crisp coherent details. No text, logos or watermark. Opaque background.

## Character and vault revision prompts — R019a

Edited with built-in imagegen on 2026-10-10. Each input was the same-named original
from `site/assets/` at `1b1f623`; each final output replaces that local file.
No external reference artwork was supplied to the editor.

### neon-emissary.png edit

Transparent background: yes. Final file: `site/assets/neon-emissary.png`.

Use case: style-transfer. Edit the supplied original cyborg hero into a striking SCI-FI GOTH fashion editorial. Keep the same single helmeted robot, portrait 1024x1536 composition, upright three-quarter pose, head/shoulders/framing and electric-green visor. Replace the Roman drape and much of the torso costume with a tailored glossy black leather high-collar coat, broad geometric harness straps worn OVER opaque armor, polished silver O-ring fasteners and buckles, ornamental chest chains, small spike shoulder accents and elegant gothic metal filigree. Strong black leather versus polished chrome contrast, acid-green rimlight and a few emerald illuminated circuit seams. Fashion-forward dark underground club aesthetic, commanding and theatrical, completely clothed; no nudity, no sexual activity, no restraint scene. Keep the original faceless helmet and professional cinematic detail, no text or logos. Preserve REAL transparent background and clean alpha around the whole figure; no painted background, floor or atmospheric rectangle. Original fictional design.

### neon-vault.png edit

Transparent background: no. Final file: `site/assets/neon-vault.png`.

Use case: style-transfer. Edit this original black-green orbital Colosseum background into a SCI-FI GOTH cathedral arena. Keep its centered symmetrical perspective, circular green portal, empty foreground floor, landscape 1536x1024 framing and dark palette. Add soaring pointed gothic arches around the central portal, intricate black-metal rib vaulting, slender spired buttresses and green-lit stained-glass-like geometric tracery. A few large ornamental suspended steel chains at the far left and right edges belong to the architecture, not people. Black obsidian, aged silver and acid-green illumination only. Majestic underground futuristic cathedral mood, elegant chrome details and thin green volumetric light. Keep the central foreground EMPTY for a separate character layer. No figures, no words, symbols, logos or watermarks. Photoreal cinematic hard-surface concept art, same restrained darkness and strong readable depth.

### neon-pan.png edit

Transparent background: yes. Final file: `site/assets/neon-pan.png`.

Use case: style-transfer. Edit this original joyful ADULT cybernetic Pan musician into a SCI-FI GOTH stage performer. Preserve his recognizable mature smiling bearded face, curved metal horns, mechanical goat legs, hoof-kick pose, complete body and synthesizer, square framing. Dress him in a fitted opaque black leather stage tunic and sculptural harness straps with silver rings/buckles worn OVER the tunic; add a studded high collar, short pointed shoulder armor, ornamental waist chains and dark gothic eyeliner. Elegant theatrical goth club fashion, playful charismatic musician, no nudity or sexual activity or restraint scene. Black chrome and glossy leather with bright acid-green instrument lights and rimlight ONLY. Keep both hands correctly playing the keyboard. All horns, hooves and instrument fully in frame. Preserve REAL transparent alpha background with no backdrop, floor, text, logos or watermark. High-end cinematic 3D detail matching the original.

### neon-revelers.png edit

Transparent background: yes. Final file: `site/assets/neon-revelers.png`.

Use case: style-transfer. Edit these two original dancing helmeted robots into a stylish SCI-FI GOTH afterparty duo. Preserve exactly two clearly robotic figures, existing disco poses, raised green cocktail, full bodies and helmets, and wide 1536x1024 composition. Add futuristic goth couture: one wears an opaque fitted black glossy leather bodysuit under a sculptural corset-like armored vest, geometric chest harness straps and a silver-ring collar; the other a tailored black leather jacket with pointed shoulders, metal buckles, wide harness straps and decorative waist chains. Both wear chunky futuristic platform boots. All garments opaque and fully covering, fashion editorial only, no nudity, sexual activity or restraint scene. Keep humorous exuberant party body language. Use obsidian black, silver chrome, acid-green #82ff52 seam lights; no other bright colors. Preserve REAL transparent background, no ground or backdrop or atmospheric rectangle. No text, logos or watermarks. Polished original cinematic sci-fi art.

## Original generation prompts (before R019a edits)

### neon-emissary.png

New original generation (R019, built-in imagegen). Transparent background: yes.
Saved in `site/assets/neon-emissary.png`.

Use case: stylized-concept. Create an original cinematic sci-fi cyborg character CUTOUT for a website hero. Portrait 1024x1536. A single elegant humanoid machine from upper thighs upward, standing with relaxed arms, body facing slightly right and head turned nearly toward camera. Broad sculpted black obsidian shoulders, long charcoal technical cloak, exquisite polished titanium armor details, smooth opaque wraparound BLACK GLASS helmet visor with razor-thin ACID GREEN luminous horizontal line. Subtle green circuit light tracing the neck, ears and wrists. Powerful mysterious presence, retro-futurist electronic music culture meets cybernetic Roman gladiator. All head and shoulders entirely visible, narrow transparent margin, dark legs may reach bottom edge. Photoreal high-end hard-surface 3D render, intense green rimlight from behind and soft silver frontal studio reflections. Palette exclusively near-black, chrome silver and electric green #82ff52. REAL transparent background; no backdrop, arena, ground, lettering, logos, UI, weapons or watermark. Original character and silhouette, not a franchise character.

### neon-vault.png

New original generation (R019, built-in imagegen). Transparent background: no.
Saved in `site/assets/neon-vault.png`.

Use case: stylized-concept. Original cinematic BACKGROUND PLATE for black-and-green sci-fi AI agent website, wide 1536x1024. Inside a vast orbital Colosseum entrance chamber: concentric monumental black-metal arches form a circular aperture centered in the image. A thin brilliant acid-green ring at the far end casts misty green rays into almost black space. Geometric black chrome fluted pillars on each side, subtle curved terraces suggest a futuristic Roman arena. Perfectly centered symmetrical composition, low horizon, glossy dark floor with thin restrained green perspective lines. Calm dark foreground with NO CHARACTERS, reserved for a separate cyborg cutout. Upper center richly detailed but subdued; corners nearly black. Film-production-level hard-surface architecture, elegant minimalist retro-futurism, volumetric haze restrained, palette only obsidian black, charcoal, electric green #82ff52 and small silver accents. No text, symbols, logos, UI, figures, watermark. Original architecture.


### neon-arena.png

New original generation. Transparent background: no.

Use case: stylized-concept. Asset: wide cinematic BACKGROUND PLATE for the Cuckoding cybernetic gladiator website. An immense futuristic circular Colosseum in space, black obsidian architecture with fine electric acid-green light seams, distant tiers of anonymous spectators, a huge luminous emerald circular gate centered above a glossy dark synthwave grid floor. Low eye-level camera, level horizon at upper third. Lower half EMPTY and calm for separate character sprites. Palette ONLY near-black, charcoal, chrome silver, electric green #82ff52, very subtle emerald haze. High-end sci-fi 3D concept art, hard-surface precision, restrained atmosphere, dramatic contrast. Wide 1536x1024 composition, no foreground figures, no weapons, no typography, no UI, no logos, no watermark. Original design, not franchise imagery.

### neon-sentinel.png

New original generation. Transparent background: yes.

Use case: stylized-concept. Asset: original transparent cutout hero cyborg for Cuckoding, portrait 1024x1536. A single powerful humanoid AI agent, chest-up with both shoulders and head fully inside frame. Polished black chrome armor, aerodynamic faceless glass visor, delicate acid-green luminous seams tracing jaw and helmet, circular earpieces, brushed titanium shoulder plates. Front-facing with slight three-quarter turn left. Elegant retro-futurist electronic musician meets cybernetic gladiator, immaculate hard-surface product-render detail, obsidian and mirror silver with electric green #82ff52 accents ONLY. Dramatic green rim light, reflective white highlights, no red/purple/blue. Subject fills frame but no crop of head or shoulders. REAL transparent background, no backdrop, floor, glow rectangle, text, lettering, logos, watermark. Original silhouette, not an existing character.

### neon-duelist.png

New original generation. Transparent background: yes.

Use case: stylized-concept. Asset: single FULL-BODY original cybernetic gladiator sprite on REAL transparent background, square 1024x1024, entire weapon and boots visible. Matte charcoal and black chrome armor with acid-green illuminated seams, angular smooth helmet/black visor, slim cape of dark technical fabric. Enters from LEFT facing RIGHT, athletic theatrical combat lunge. Holds a long straight luminous green-edged SWORD in both hands; hilt at lower center, blade extends diagonally UP-RIGHT toward upper right, fully inside image. Body mainly left half, sword in right half, minimal transparent margin. High-end cinematic hard-surface sci-fi 3D art matching black/green retrowave arena, precise titanium details and dramatic green rim light. No ground, background, additional figures, gore, text, logos or watermark. Original design, not franchise imagery.

### neon-secutor.png

New original generation. Transparent background: yes.

Use case: stylized-concept. Asset: single FULL-BODY original cybernetic gladiator sprite on REAL transparent background, square 1024x1024, all feet and weapon fully visible. Heavy brushed titanium and obsidian armor, angular hornlike helmet fins and black glass visor with thin green slit, acid-green illuminated mechanical joints. Enters from RIGHT facing LEFT in athletic theatrical combat lunge. Holds a MORGENSTERN: long rigid dark shaft with glowing green-spiked metal ball at the tip, not a chain flail. Hands lower center, shaft extends diagonally UP-LEFT so it can cross another sprite's sword. Body mainly right half, weapon left half, minimal transparent margin. Cinematic hard-surface sci-fi 3D detail, reflective silver/black, green #82ff52 rim light, no other colors. No ground, backdrop, other figures, gore, text, logos, watermark. Original character.

### neon-humans.png

New original generation. Transparent background: yes.

Use case: stylized-concept. Asset: independent foreground group for Cuckoding satirical website finale, REAL transparent background, wide 1536x1024. Three melancholy ADULT humans in modest charcoal futuristic jumpsuits sit on low black metal blocks. One exhausted person rests head in hands, another gazes sadly upward, third slumps carrying an absurdly large dark spherical weight; oversize metallic chains with faint electric-green glowing links connect wrists to weights, a symbolic burden of outsourcing all pleasure to AI. Dignified expressive faces, no injuries, no gore, no nudity, no children. Complete people, chains and weights entirely in frame with narrow transparent margin; no ground, background, robot, words, UI, logo or watermark. High-end cinematic 3D sci-fi concept illustration, obsidian/chrome and restrained green rim lighting matching neon cybernetic gladiators. Tragicomic mood, detailed believable humans, dark matte materials.

### neon-pan.png

New original generation. Transparent background: yes.

Use case: stylized-concept. Original satirical foreground sprite on REAL transparent background, square 1024x1024. One joyful ADULT cybernetic Pan/satyr, human face with dark beard, curved metallic horns, mechanical goat legs and hooves, fully clothed in modest black technical tunic. A small silver synthesizer is strapped across his body; fingers play keys as he kicks a hoof in a playful dance, leaning right. Entire body horns to feet and instrument visible. Obsidian and brushed chrome materials, electric green #82ff52 illuminated seams, high-end cinematic sci-fi 3D concept art, funny but polished. No background, ground, other figures, text, logos, watermark, gore or nudity. Strong green rim light, no pink/blue/red, realistic material precision.

### neon-revelers.png

New original generation. Transparent background: yes.

Use case: stylized-concept. Original satirical foreground sprite on REAL transparent background, landscape 1536x1024. Two delighted cybernetic robots dancing together at the Colosseum afterparty. Elegant black-chrome faceless helmets and silver armor with thin electric-green illuminated seams; one raises a green glowing cocktail goblet, the other performs a ridiculous exaggerated disco pose with one arm up and bent robotic knee. Full bodies and all feet and hands visible, figures facing a little left, no floor or background or other people. Playful relaxed robotic body language, not combat. High-end cinematic sci-fi 3D concept art, obsidian chrome silver acid-green #82ff52 ONLY, precise materials, green rim light. No typography, logos, watermark, gore or licensed characters.
