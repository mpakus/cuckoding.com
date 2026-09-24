# 1036 — Classic and irony illustration modes

Claimed by Codex on `feature/1036-pages-irony-mode`, based on clean `main` at
`55a9415` (the previous Pages design is now committed on main and origin/main).

## Acceptance and approach

The user requested two visual modes: unchanged existing images, plus humorous
satire about humans serving robots, with the same pearl/violet art style.
Add native radio controls, use Irony as the default/no-JS view (updated at user request), switch
all three images and their accessible text/captions, and remember the choice
without breaking interaction when browser storage is denied. Product claims
remain grounded in the current source. Verify the switch, persistence/fallback,
keyboard behavior and narrow layout.

Applied Ponytail full 4.10.0 (MIT), repository minimalism and quality gates,
built-in ImageGen, better-ui and better-accessibility. Required product/security
documents and site implementation were read in this task chain; inspected the
current clean checkout, task 1035, and site/motion verifier before editing.
This uses the existing static DOM/native controls, no unfamiliar runtime or
adapter problem and no peer code adaptation or XERJ-completion claim.

## Evidence

`rtk proxy` is used for exact source reads, image encoding and
inline verification scripts, preserving argv/output semantics.
Verification passed:
- `rtk node test/github_page_art_mode_test.cjs`: default Irony, saved Classic and Irony,
  invalid/denied storage, repeated mode changes, all three image sources/alt
  texts and six captions, and hidden no-JS control.
- `rtk node test/github_page_motion_test.cjs`: initial/changed reduced motion,
  visible content and bounded parallax.
- `rtk node --check github.page/script.js`: pass.
- `rtk ruby github.page/verify.rb`: 9 local references, 4 pinned actions;
  both image sets satisfy their 400 KB budget.
- `rtk git diff --check`: pass.
- `rtk proxy python3 - <<'PY'` compared each existing `pearl-*.webp` byte-for-byte
  with `git show HEAD:<path>`, calculated asset sizes/SHA-256, and checked
  the three new URLs on port 4115: unchanged originals, HTTP 200 image/webp.

Rendered verification used CUA on http://127.0.0.1:4115/:
- Clicked Irony, reloaded, and observed the saved radio selection and satirical
  artwork/captions. Keyboard ArrowLeft restored all original sources; ArrowRight
  restored Irony. Selection remained exclusive and keyboard focus stayed visible.
- Desktop 1440×1000, mobile 390×844 and narrow 320×740: no horizontal overflow.
  Both mode targets measured at least 44 px high; keyboard focus outline 3 px.
- Inspected all three scenes, including lazy-loaded knowledge artwork. All new
  images decoded successfully; no browser warnings/errors.
- Shifted only the Irony hero badge to the right to avoid covering the human's face.
  Classic image bytes and presentation are preserved.
- New controls use native fieldset/radios, a named group, selected dot, and live
  status text. Storage exceptions keep the in-page control usable. Without JS,
  Irony remains visible and the unavailable control stays hidden.

No dependencies or application runtime changes. Elixir/native shell gates are
not applicable to this static-site change. Live GitHub Pages deployment was not
run; the preview stays available locally.

## Generated illustrations

Three original built-in ImageGen calls; no external images or reference uploads.
Exported with `rtk proxy cwebp -q 82 -resize WIDTH 0 INPUT -o OUTPUT`
(crew width 1536, others 1200). Each original is under
`/Users/mpak/.codex/generated_images/01a0d13a-30c0-71d3-83ed-4308c276bcde/`.

| Asset | Original PNG | Final dimensions | Bytes | SHA-256 |
| --- | --- | --- | ---: | --- |
| `github.page/assets/irony-crew.webp` | `exec-5cd60a28-081a-40da-9849-8716c5fa8f4f.png` | 1536×1024 | 151746 | `4cda128c5a9c23685a015eb96c9d73f747416e8453372292a3b1eb66c3c88890` |
| `github.page/assets/irony-path.webp` | `exec-fdc97334-ba4d-44f6-b362-5ac787a8b926.png` | 1200×800 | 128176 | `8b1171e319a182bacb0987942236d7935d25a36d53bf06e63c14832361beea51` |
| `github.page/assets/irony-knowledge.webp` | `exec-7cc3cb2c-0e2c-458e-a015-58c6aa714c7f.png` | 1200×800 | 112074 | `d246989cde5d9f784ae58cf704a971eea8487a9b0eacf591da53cfc30fd0e214` |

Total new image payload: 391996 bytes.

### Hero prompt

Use case: stylized-concept. Asset type: original satirical alternative hero illustration for Cuckoding, 3:2 landscape. Same sophisticated pearl-white, cool silver, pale mist-blue and restrained amethyst-violet science-fiction visual language as an elegant productivity app. Premium sculptural 3D concept art, matte porcelain robots with black glass faces and tiny violet eyes, brushed titanium furniture, frosted lavender glass, diffuse daylight, painterly atmospheric distance. Scene: on a gorgeous futuristic terrace with a giant silver ring portal and misty white city spires, two smug small ivory robot executives recline comfortably in luxury chairs with their mechanical feet on an extravagant silver desk. One robot delicately sips tea, the other lazily points at a tablet. Their adult human developer attendants are visibly doing all the work: a rumpled exhausted programmer carries an absurdly tall carefully balanced stack of blank reports and three coffee cups; another weary adult human kneels beside the desk plugging in a comically tangled power cable while rolling their eyes. Satirical role reversal: automation has freed the robots to relax while humans have become their overworked servants. Dry visual office humor, comic timing, expressive human eye-roll, amusing rather than grim. Keep the working humans and lounging robot bosses clearly together in the RIGHT two-thirds, full important subjects away from extreme edges, left third airy silver-white mist. Lower edge softly fades into pearl haze for an interface caption. The humor must be evident from the poses and props, not text. No violence, chains, injury, historical slave imagery, erotic content, text, letters, logos, readable screens, watermarks, or UI. Humorous original illustration, not a product screenshot.

### Workflow prompt

Use case: stylized-concept. Asset type: original satirical workflow illustration for Cuckoding, 3:2 landscape. Pearl-white, silver, pale mist blue, restrained amethyst violet. Premium finely detailed 3D concept art with gentle painterly atmospheric light, ivory porcelain robots with black glass faces and tiny violet eyes, translucent lavender details. Scene: an elegant curved ivory walkway through three monumental silver ring gateways above clouds, leading toward a distant futuristic city. In the lower central foreground two weary adult human programmers in rumpled modern office clothes are carefully carrying a ridiculously ornate, lightweight silver sedan chair. A very small smug robot manager reclines in the chair like royalty, feet up, holding a tiny lavender parasol and lazily inspecting a blank glass tablet. A third adult human ahead is unrolling a pearl-lavender carpet for the robot. The humans exchange exasperated side-eye; the absurd little robot is being pampered while all progress is literally carried by humans. Clear humorous role reversal, sarcastic office culture satire: the humans do the heavy lifting for their automated boss. Important figures occupy center of lower two-thirds and are readable together, no one at extreme edges. Same calm luminous futuristic refinement as a premium pearl productivity interface; elegant architecture rather than a cartoon comic. No words, letters, numbers, logos, UI, diagrams, watermark, violence, chains, injury or historical slave imagery.

### Knowledge prompt

Use case: stylized-concept. Asset type: original satirical knowledge illustration for Cuckoding, 3:2 landscape. Refined high-key pearl-white and cool silver 3D science-fiction concept art with pale mist blue and restrained violet glass. Matte ivory ceramic robots with black glass faces and tiny violet eyes, brushed titanium, soft painterly atmosphere, diffuse daylight. Scene: an enormous beautiful floating faceted amethyst knowledge crystal above a circular layered ivory archive pedestal, blank glass document slabs spiraling around it. Next to the crystal, an extremely comfortable tiny robot librarian lounges in an elegant silver chair, feet up, wearing a miniature silver crown and holding a porcelain espresso cup. Two adult human developers are its overworked assistants: one exhausted human rides a small stationary bicycle with a visible cable connected to the glowing crystal pedestal, powering the machine; the other human carries an absurd tall stack of blank glass document tablets toward the archive and gives the robot a sarcastic side-eye. The joke is crystal-clear: the robot has outsourced both intelligence maintenance and physical labor to its humans, then takes the credit. Whimsical corporate overlord satire, not cruelty. Crystal slightly left of center; robot and both humans clustered within central/right two-thirds so a 6:5 crop keeps their complete bodies. Misty white spires and subtle silver arch in distance. No writing, letters, numbers, logos, readable screens, interface, watermark, violence, chains, injury or historical slave imagery.

## Default mode and main integration

User requested Irony as the default and completion/merge into main. The HTML,
hero preload and social preview now start with Irony. The switch restores a
saved Classic choice; missing, invalid or unavailable storage uses Irony.
Updated the focused check for all of these states and no-JavaScript artwork.
Applied the repository security-review skill to local Git integration: only
this task's inspected files are staged, no credentials or new capabilities,
no destructive Git operations, and no remote publication.

Final checks passed after the default changed:
- `rtk node test/github_page_art_mode_test.cjs`
- `rtk node test/github_page_motion_test.cjs`
- `rtk node --check github.page/script.js`
- `rtk ruby github.page/verify.rb` (9 local references, 4 pinned actions)
- `rtk git diff --check`

CUA confirmed Irony as the HTML checked default and all three default image
sources. Selected Classic, reloaded, and verified the saved selection and all
three original images, then restored Irony for the preview. No browser errors
or warnings. Existing desktop/mobile layout checks remain valid; this follow-up
changes only the default data and preference fallback.
