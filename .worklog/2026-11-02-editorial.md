# Marketing refresh and application visual system

## Scope and baseline

Owner request: refresh cuckoding.com copy, add two or three sarcastic/ironic
illustrations, and apply the marketing site's minimal visual style and animation
to the BOSS application. Baseline local main 003941b, clean; fresh origin/main
also resolves to 003941b. The previous autonomy increment passed 660 tests with
one Linux-only skip, plus 33 checks after local integration.

Isolated writers own site markup/style/checks, application shell/tokens/motion,
and application view/component presentation. Root owns generated assets, shared
documentation, integration, browser acceptance and website publication. Website
publication uses the fresh remote baseline and an explicit website-only allowlist.
The running 4001 instance and its data are not part of independent preview setup.

## Design contract

The live public hero, editorial text section and product workflow were inspected
in the browser. Adopt the site's paper #f6f3ea, ink #252a24, muted #62675c,
peach #f1d4c2, sage #dce7d8, line #c8ccc0 and surface #fffdf7. Use Helvetica
Neue/Arial with occasional Georgia italic emphasis, thin rules, near-square
corners and restrained motion. The application's primary job remains selecting
projects and inspecting/controlling work, with compact evidence panels and clear
Stop actions. No decorative art or oversized landing-page hero inside task data.

Required states: empty projects/tasks, active work, waiting/attention, error,
selected task/revision, unavailable agents and locked browser. Keep URL-owned
selection, native dialog focus and existing form/event contracts. At narrow widths
only the labeled board region may scroll horizontally. Motion must respect the
OS preference, a visible pause control and keyboard interaction; no idle animation
loop or moving status data. All marketing content remains accessible without JS.

## Research

`rtk proxy xerj search --prefix bossrefs 'LiveView layout CSS transition reduced motion' -k 3`
could not reach localhost:9200. Direct fallback read
`examples/agent-orchestrator/frontend/src/renderer/styles.css:676` and
`frontend/src/renderer/components/ui/multi-step-loader.test.tsx:8` at pinned
7193eff4e08f1481944845ee058fe6fd18930b6d; root license is Apache-2.0.
Adopt reduced-motion handling and transitions tied to actual state changes;
reject padding animation, fake progress percentages and the reference product's
visual layout. No reference code was copied. Primary brand reference is our own
site/styles.css and existing artwork. The external web reader could not fetch the
public site; the browser loaded it successfully.

## Verification

Focused checks, cross-review, browser acceptance and website publication are
complete below. Provider calls and application deployment are outside this scope.

### Implementation and verification receipts

- Site writer19fc8af; shell a549c3b; views01be9da. Independent cross-review
  found no control/event/security changes. Root integrated sequentially.
- Three built-in Imagegen outputs encoded with installed cwebp, full1536x1024
  q80 and small768x512 q78. Exact generation prompts in docs/SITE.md.
- `rtk proxy env MIX_DEPS_PATH=/Users/mpak/www/elixir/cuckoding.com/deps asdf exec mix test test/boss_web --seed 1210`:150passed in17.3s.
- `rtk proxy node --test test/app_motion_test.mjs test/site_motion_test.mjs`:11passed.
- Initial assets.build with external MIX_DEPS_PATH failed relative Phoenix JS
  imports. Private APFS dependency copies restored expected local deps paths;
  `rtk proxy asdf exec mix assets.build` then passed. No dependency change.
- `rtk proxy asdf exec mix format --check-formatted`:passed.
- Website checker:43links/assets; checker self-test:10malformed fixtures;
  site motion6/6. Browser320/768/1024/1440px: no document overflow/missing art.
  New second-opinion stage and pause toggle worked; ring/award art uncropped.
- Fresh `git fetch origin main` retained003941b. Ancestry and explicit site/docs
  allowlist verified before `git push origin HEAD:main`; published5a6d15c.
  Pages41579508007 check/deploy succeeded. Python HTTPS check first failed local
  CA-store configuration; system curl with normal TLS validation matched19files.
- Real LiveViews rendered into8 private fixture pages with current built assets,
  isolated test DB and repository. Generator1/1passed; session/CSRF data removed.
  No real workflow/provider calls or running4001 modifications. At320px all8
  pages fit; persisted motion pause and keyboard transition suppression worked.
  Browser found upward Tab could obscure a field under the sticky drawer header;
  writer is applying a non-scrolling header/separate body fix before acceptance.

### Browser corrections and final acceptance

- 2f9dcfe separates the native drawer header from its scrolling content. At320px,
  upward Tab now keeps all5 focused controls below the113px header and onscreen.
- Review identified the allowed200-character title boundary. Actual320x568
  reproduction measured617px header and40px padding-only body. 8f3e774 bounds
  the scrollable header to40dvh while preserving its full accessible text.
  Final browser measurement: header227.19px/body340.81px; focused reviewer
  top375.95/bottom419.95 inside viewport. Independent review approved both fixes.
- Final private rendering9pages passed; all8 ordinary pages fit320px. Home,
  project and drawer also fit768/1024/1440px. No console warnings/errors.
  Browser preview is static; connected behavior is covered by the web test suite,
  not represented as a real running-provider or production-instance acceptance.
- Motion preference persisted through reload and keyboard input switched movement
  off. An isolated OR→AND mutation of reduced-motion logic failed4 of5 existing
  tests; tracked implementation remained unchanged.
- Final assets.build passed. Screenshots retained in the conversation's
  visualization directory: boss-editorial.jpg and cuckoding-office-live.jpg.
- Focused drawer checks after changes:18passed for normal scrolling,11passed
  for the long-title header. Final local-main web regression follows integration.

### Outcome and next step

Requested website is live at5a6d15c, exact successful Pagesrun41579508007.
Application source is ready for local-main integration; the running4001 instance
and original data remain untouched. Next: verify merged main, remove clean merged
worktrees and leave application activation to its normal next build/start.
