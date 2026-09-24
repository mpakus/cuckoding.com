# 1039 — GitHub Pages product copy

## Scope and acceptance

Expand the existing marketing page from `docs/PRODUCT.md`: explain who it helps,
the planning/review/delivery loop, reusable agents and models, additional roles,
parallel tasks, pause/stop controls, evidence, metrics and reviewed knowledge.
Correct the old manual-only completion claim. Preserve the approved design,
artwork modes, truthful source-versus-release status and existing runtime limits.
Validate the static surface and rendered desktop/narrow layouts; do not claim
remote publication or native/provider acceptance from these checks.

## Starting state and sources

- Clean local main at `2a4264c`; feature branch
  `feature/1039-pages-product-copy`. Task 1038's native acceptance remains blocked.
- Primary source: `docs/PRODUCT.md`, especially default roles, MVP capabilities
  and primary journey. Cross-checked `docs/FLOW.md`, `docs/TESTING.md` and the
  current public HTML/verifier. Existing source and fixture evidence support the
  capability copy; native/provider evidence remains explicitly pending.
- Ponytail full, version 4.10.0 (MIT), Better Writing, and repository quality
  gates applied. Reuse current markup and styles; no dependency or framework.
- RTK proxy exceptions: source reads and bounded structural/browser-preview
  support require exact unfiltered content or command semantics. No unfamiliar
  implementation or borrowed source, so no peer-code adaptation is needed.

## Changes and claim grounding

- Hero and social/search descriptions now explain prompt/plan → agent work →
  progress/evidence/control. The introduction names developers and small teams.
- Six journey steps cover project setup, path discovery and reusable agents,
  prompt/committed Markdown planning, independent proposal review and selective
  import, delivery, and manual/default or automatic/local completion.
- Role descriptions use Speculator, Implementor and Reviewer, including the
  bounded correction loop. Six existing-style feature panels cover concurrency,
  controls, supported additional roles/grants, evidence/history, labeled metrics
  and optional connectors. Knowledge copy includes reusable skills.
- Grounding: PRODUCT's role contract and primary journey support the six steps;
  its MVP capabilities support controls/metrics/plugins/knowledge. TESTING and
  task 1038's worklog support the simulated-agent evidence and remaining native
  and real-provider gaps. The current implementation status is not presented as
  a public release or a verified unattended real-provider experience.
- Added a product-specification link beside release evidence. Preserved the
  supported/setup-only adapter distinction, host-runner limitation, separate
  release approval and no autonomous merge/deployment claim.
- Updated `docs/UI_DASHBOARD.md` with this public-copy contract. No CSS,
  JavaScript, illustrations, workflow configuration or native code changed.

## Verification

- `rtk ruby github.page/verify.rb`: passed, 9 local references and 4 pinned actions.
- `rtk node test/github_page_art_mode_test.cjs`: passed defaults, preference
  restore, invalid/denied storage, repeated switching, alt text and captions.
- `rtk node test/github_page_motion_test.cjs`: passed initial/changed reduced
  motion, visible content and bounded parallax.
- `rtk node --check github.page/script.js`: passed.
- CUA preview at 1280, 390 and 320 px: both modes rendered; document width
  matched viewport width in every mode/width pair. Read-only DOM checks found
  no clipped paragraphs, headings, role tags or routes at narrow widths.
  Screenshots inspected desktop composition, mobile flow/roles, narrow board
  and release-status wrapping. Six steps and six feature panels rendered.
- Native radio ArrowLeft/ArrowRight changed mode, focus and live status;
  reload retained Irony. All three Irony images loaded. Browser reported no
  warning/error entries. Viewport override was reset.
- `rtk git diff --check`, changed Markdown link validation and HTML element
  nesting checks: passed. Existing structural checks are proportionate to this
  copy-only change; no invented product test or full native rebuild is needed.

The temporary static preview and browser tab were closed after inspection;
port 4115 is closed. No remote push or Pages deployment was performed; the
running native application is unchanged. The final four-file change is committed
on the task branch for fast-forward integration into local main.
