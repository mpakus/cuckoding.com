# Cuckoding marketing site — 2026-10-29

## Scope and baseline

User requests a professional, funny, ironic and satirical marketing site for
cuckoding.com, hosted from the repository with GitHub Pages: humans serving AI
while agents enjoy the rewards, with original pictures and parallax.
Baseline local main23061d263042d2e7d714f693e203749a96aebba7. Parent checkout is
on codex/boss-release-acceptance with unrelated dirty tasks/todo.md and daily
worklog; preserved. This owner works on codex/cuckoding-marketing in its isolated
managed worktree. Separate Pages writer owns workflow/check script only; parent
owns all shared docs. Local merge is authorized by AGENTS; remote publishing is
separate. Current remote main remains the previous product.

## Design contract

An editorial luxury resort for AI: cream/ink/peach/pool-green palette, oversized
sans with italic serif accents, photographic absurdism, generous but purposeful
spacing. Hero explains the joke; arrangement grounds the real product; an
interactive illustrative workflow explains human control; fine print states
actual development status. Primary action goes to the GitHub project, secondary
action explores workflow. No invented testimonials, usage figures or downloads.
Mobile stacks artwork/text; no horizontal page overflow at320px. Content works
without JS. Motion stays on decorative artwork, coalesces frames, respects live
OS reduced motion and an explicit page toggle. Reject generic neon AI gradients,
scroll hijacking, autoplay videos and dependency-heavy animation libraries.

## Research and provenance

Read BOSS_PLAN.md, tasks/plan.md, tasks/todo.md, latest daily worklog and
examples/README.md. Verified asdf Elixir1.20.3 / OTP28 ERTS16.4 against
.tool-versions. Runtime is unchanged by this static site increment.
Query: `rtk proxy xerj search --prefix bossrefs 'prefers-reduced-motion' -k 3
--full 1500`. Sandbox attempt failed to reach local node; independent researcher
reran successfully with escalation. Read examples/agent-orchestrator/frontend/src/
renderer/components/settings/PairingQr.tsx:14-15,80-95 and tests:167; also
components/chat/ChatTimelineItems.tsx:189-204 and tests:304-322. Pin
7193eff4e08f1481944845ee058fe6fd18930b6d, Apache-2.0. Adopt OS preference,
live matchMedia changes and cancellable/coalesced frames; reject React/two-canvas
architecture and typewriter effects. Independently implemented; no code copied.
Existing remote Pages workflow uses main-only deployment, site-only artifacts
and pinned official actions. Preserve those boundaries, replace old-product
checks. GitHub API confirms CNAME cuckoding.com but current certificate transition
is not successful deployed-site evidence.

## Work in progress

Sites guidance used for presentation/local preview; user's explicit GitHub Pages
hosting takes precedence over Sites hosting. Ponytail, frontend, Git, imagegen
and browser-testing guidance apply. Built-in imagegen generated two original
robot-resort/spa images; prompts and final asset provenance will be in docs/SITE.md.

## Implementation and verification

Independent Pages writer committed96adebda22552f0391a0d29a1b673f29ecbd8d75;
merged sequentially into the site branch. Parent owns site/, motion tests,
AGENTS.md, docs/SITE.md and appended task documentation. No runtime, migration,
release script, provider account, user data or source-spec change.

Generated original artwork with built-in imagegen. Converted to WebP using
`rtk proxy cwebp -quiet -q82` (hero1536px/spa800px) and q80 hero768px.
All assets total448KiB. System fonts avoid external requests. Exact prompts and
asset paths recorded in docs/SITE.md.

Actual commands and outcomes:
- `rtk proxy python3 -B scripts/check_site.py --self-test`: valid fixture and10
  malformed fixtures passed.
- `rtk proxy python3 -B scripts/check_site.py`:26 links/assets passed.
- `rtk proxy node --test test/site_motion_test.mjs`:6 passed,0 failures.
- `rtk proxy python3 -m http.server 8765 --bind 127.0.0.1 --directory site`:
  local preview served using authorized network escalation after sandbox denial.
- CUA in-app browser:320/768/1024/1440 widths equal document scrollWidth; both
  images loaded, console warnings/errors empty. CTA, all4 stages, Enter activation,
  deep-link reload, native FAQ, pause/resume and back-to-top verified.
- Initial320px screenshot exposed intrinsic aspect-ratio overflow; explicit
  image-frame width/min-width fixed the cause. Tablet hero stacks below900px to
  retain both subjects. Independent review caught3.90:1 hover contrast; .75
  opacity corrected it to6.11:1. Reviewer approved and independently ran6 tests;
  an isolated reduced-motion mutation produced3 failures, original source intact.

Browser screenshots are retained in the chat visualization output. No remote
write or deployment; current domain/certificate health is not claimed. This
static site does not need another Elixir/application acceptance run.
