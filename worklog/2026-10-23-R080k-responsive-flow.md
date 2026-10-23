# R080k — Responsive setup-to-Start flow

Claimed on `feature/R080k-responsive-flow`, base `0b8abb3`. R060o is merged and
verified locally. User untracked `Untitled.md.age` remains unread/unstaged.

Scope: one full setup-to-Start UI path, empty/error states and dialogs, at 320,
768, 1024 and 1440 CSS pixels, keyboard/focus and reduced motion. Use separate
source-development data, backup before schema-sixteen to seventeen migration,
no provider sign-in/inference or original saved workspace access. Existing
near-black/green one/two-region design and shared native dialogs remain.

Ponytail full 5.3.2 MIT, RTK, LiveView, frontend-ui-engineering, better-layout,
better-accessibility, quality and security guidance apply. This is focused flow
implementation/verification, not a whole-product cross-discipline approval.

## Findings and changes

The old `.tabula-columns` rule explicitly allocated five grid columns. A workflow
with a custom stage rendered Completed on a second row. Use implicit column flow
and the same minimum widths so all stages remain in order in one horizontal row.
Keep the existing focusable region and add a visible hint/description. No extra
navigation or workflow state was added.

Task +/Edit previously dispatched `cc:open` immediately while sending `edit` to
the server. The dialog could accept input before selection replaced the form
identity. Now the guarded parent selects the exact task (or dirty-draft decision)
and sends `dialog-open` after its DOM patch. The shared hook checks the exact
dialog ID and reuses native showModal/focus/Escape/return. Immediate static dialogs
and all domain/authorization behavior remain unchanged.

The new LiveView regression first failed at the missing server event (9/10 tests
passed); the hook test first failed because no `dialog-open` handler existed.
Both pass after the fix. A foreign dialog ID never opens this editor; an invalid
task ID never emits opening authority. Existing dirty-draft confirmation remains.

## Browser and data evidence

Private source QA data was schema sixteen with only settled commands and one
Stopped fixture battle. The shell lock was unheld. A SQLite backup under that
exclusive lock passed integrity/FKs; SHA-256
`f8e76c90243b3146db7222ff44b75d7befdf89fd2fba67a2835423a1fde6b370`.
Source startup migrated this QA database to seventeen. After browser shutdown,
all fourteen domain table hashes remained identical to the backup; integrity/FKs
passed and the shell lock was available. No profiles were imported, login/inference
ran or original workspace was accessed.

The private launcher follows `bin/dev.server` and writes a one-use local handoff
to a mode-0600 temporary file instead of invoking a system browser. The browser
consumed/unlinked it, retained a private temporary session for the checks and
deleted that session after graceful launcher shutdown. No token was printed.

Bundled Playwright's browser downloads were absent, so the harness used installed
Chrome in a fresh isolated headless context, never the personal browser profile.
The first browser initialization did not reach an authenticated main page after
harness setup delays; restarting only the verified idle QA launcher normally
supplied a fresh handoff and succeeded. Tailwind's watcher initially served
old CSS, so an explicit `mix assets.build` was completed before final browser
verification. Production CSP correctly refused an inline-style test injection;
the regression subsequently replaced only that browser's same-origin stylesheet
response, without weakening CSP. Native keyboard animation was awaited before
checking the last column; a dialog check was corrected to allow focus in browser
chrome, while refusing every background element. Reopening assertions wait for
the server-confirmed dialog rather than reading a hidden old form.

Final private harness `.ccoding/r080k-browser-after.cjs` passed:

- Eight pages at 320/768/1024/1440 CSS pixels (32 states), no page-wide horizontal
  overflow or JavaScript page errors. Sidebar/journey/board retain intentional
  internal scrolling. The profile-free fixture's Start stays correctly disabled
  by its incomplete bindings; no Start or provider action was clicked.
- Six workflow columns share one row at every width. The old five-column CSS
  replacement fails this assertion. Focusing the board and pressing ArrowRight
  reaches its final column; visible hint and accessible description match.
- Create tasks, Board team and task editing fit at each width (12 dialog states).
  Tab never focuses background content; Escape closes and returns to the opener.
  Chrome's own chrome is a valid native focus destination, not a trap failure.
- The task form identity is patched before native opening. Immediately entered
  unsaved text survives a 5.5-second tick interval and close/reopen. No Save ran.
- OS reduced-motion was enabled during this pass. This does not claim every
  animation, screen-reader behavior or actual browser zoom was audited.

Before/after desktop/narrow screenshots, dialog captures and metrics are private
`.ccoding/r080k-*` artifacts. Inspected the narrow roster, Team desktop, Arena
before/after and task dialog visually. Full acceptance remains in PLAN.

## Verification

- Pinned Elixir 1.20.3-OTP28 / OTP 28.5 / Rust 1.97.1 PATH is the same as R060o.
- `rtk proxy env PATH=<pinned> mix test test/cuckoding_web/tabula_live_test.exs test/cuckoding_web/workflow_live_test.exs`:
  **17 passed** after the server-opening fix.
- `rtk proxy env PATH=<pinned> mix quality`: **553 passed**, formatting,
  warnings-as-errors compile, strict Credo, Sobelow and dependency audits passed.
  Existing migration/dependency warnings remain. An earlier 552-test pass preceded
  the additional behavioral regression; only 553 is the final scope.
- `rtk proxy node --test test/dialog_test.mjs test/agent_login_test.mjs test/activity_follow_test.mjs`:
  **5 passed**. After stopping the preview, inverted the new dialog ID condition:
  foreign-ID regression failed. Restored exact bytes in `finally`, then all five
  passed again. No watcher/provider saw the mutated source.
- `rtk proxy env PATH=<pinned> mix assets.build`: passed before final browser checks.
- Source QA launcher was stopped with Ctrl-C. Port 56103/listener and data lock
  were verified free; terminal completion is checked before handoff. Only that
  owned preview was stopped.

Native Rust source is unchanged from R060o's 97 passed / 5 ignored scope, so that
suite is not claimed as rerun here.

`rtk proxy env PATH=<pinned> bin/dev.build` passed, including strict/deep ad-hoc
sealing. `rtk proxy bin/smoke` passed bundled launch/bootstrap, cookie, handoff
replay/origin refusal, heartbeat, graceful quit and listener cleanup. Fresh smoke
data remains `/private/tmp/ccoding-smoke.EFWqq1`. Verified both current unhashed
and cache-manifest-selected CSS/JS contain the one-row grid and server-open hook.
Older immutable fingerprint files were excluded from this current-asset check;
the first harness incorrectly inspected every historic fingerprint.

Final bundle helper SHA-256:
`499cbb1a2be9006add68f5ed5f729664946b30a6c2ce457734c8b1330631dece`.
Resource-manifest SHA-256:
`f34a0ef7d72ab89dd2d6f3e66e7dcaa87b126c591d213d66ac43391961e7f29d`.
Source-launcher terminal completed with exit 1 after Ctrl-C; its graceful backend
shutdown, listener removal and lock release were separately verified before build.

Reviewed the final diff for selection/open ordering, session/scope guards, exact
dialog targeting, dirty-draft behavior, shared native focus handling, stage order
and bounded scrolling. Installed Phoenix `push_event` documentation explicitly
confirms default dispatch after the LiveView patch (`deps/phoenix_live_view/lib/phoenix_live_view.ex:866-868`).
No unresolved slice finding. Documentation links and `git diff --check` passed.
No human ten-minute, screen-reader/zoom, actual provider, forced sleep or
clean-machine release acceptance is claimed. Local integration pending; no push.
