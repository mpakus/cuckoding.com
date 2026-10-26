# BOSS-005 — task board and drawer

## Scope and baseline

- Start from clean local main `36534aa`, reused primary checkout on
  `codex/boss-board-integration`. Previous verified suite: 140 passed, 1
  Linux-only skipped. Effective Elixir 1.20.3 / OTP 28 confirmed this turn.
- Five board columns from saved task states; a URL-addressable task drawer with
  pinned/selected source revision, current source metadata and actual task events.
  Preserve selection and revision while specs refresh. Keyboard, focus, narrow
  screens, empty/loading/error states and source escaping are acceptance criteria.
- No task execution controls or invented run/agent/check/review metadata. Existing
  dark design stays consistent; application-wide theme polish remains Phase 5.
- Backend writer owns Tasks detail query/tests; UI writer owns board/drawer,
  LiveView/hook/tests; reviewer is read-only. Root owns router/layout, integration,
  browser verification and shared docs. Each writer uses an isolated managed
  worktree and `codex/` branch.

## Reference coding and design

- Read BOSS_PLAN minimal UI/Phase 1, tasks plan/status, AGENTS and latest worklog.
  Used Ponytail, frontend-ui-engineering and browser-testing-with-devtools skills.
  Browser verification will use available CUA browser capabilities; no additional
  browser dependency is needed.
- xerj `TaskDetailDrawer` found no match; `drawer selectedTask` found Kander's
  identity-based SelectedTask and unrelated mobile UI. These are research leads,
  not proof of a browser implementation. Follow-up queries from agents:
  `Kanban drawer focus DialogContent`, `kanbanColumn`, `task detail revision history`,
  `getTask taskId projectId`. Read concrete sources/tests after weak results.
- Agent Orchestrator (Apache-2.0), SHA
  `7193eff4e08f1481944845ee058fe6fd18930b6d`:
  `backend/pkg/contract/kanban.go:5`,
  `packages/product-ui/src/SessionsBoardView.tsx:193` and its test at line 93.
  Adopt derived state grouping, headed lanes and stable card identity; reject
  demo cards and PR/mergeability-based completion semantics.
- Backlog (Apache-2.0), SHA `3580cfbbb1be4144a5cca5b49190e1f8158e4cf7`:
  `packages/server/src/routes/tasks.ts:187`, `board-multi-project.test.ts:26` —
  project-scoped detail lookup. Reject `packages/board-ui/src/lib/DialogShell.svelte:23`:
  aria-modal alone does not supply focus trapping or inert background.
- Kander (MIT), SHA `dea0ba6b885c39a56ee769223f7fa5c054e68c70`:
  `internal/board/snapshot.go:21` and `snapshot_context_test.go:36/196` —
  coherent pinned reads; reject whole-board/runs loading and file journal locks.
- Native dialog behavior checked against [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/dialog).
  Installed LiveView `lib/phoenix_live_view/js.ex:1050` explicitly demonstrates
  `JS.ignore_attributes("open")`; preserve that attribute while updating content.
  [Tailwind has variant](https://tailwindcss.com/docs/hover-focus-and-other-states#has)
  widens only a root shell containing the board, including live navigation.
- Design contract: retain project navigation and Sync, group compact cards by
  actual state, preserve stable IDs, constrain horizontal overflow to the board.
  Native modal dialog supplies focus trapping; a small hook handles opening,
  Escape and focus return. The URL owns task/revision selection. Source is
  escaped plain Markdown; no new Markdown-rendering or UI dependency.

## Progress

- Delegated backend read model, UI and independent review; scope fixed before code.
- Task detail query must join the requested project before exposing source/events,
  read one consistent snapshot and stay bound to one Repo PID. Revision options
  contain metadata only; the drawer reads one selected source and latest 50 events.
- Protected task route/root-shell change committed `08e531d`. The existing narrow
  Projects/Unlock layout remains; board width follows DOM presence rather than
  a root-layout assign that would become stale after live navigation.
- Backend `06e826e7` integrated after source review. Eight new tests cover pins,
  revision selection, scope, missing history, bounds, raw text and storage errors.
  Writer reported 29 focused and 148 full passed / 1 existing Linux skip;
  compile/format/diff-check passed. Root combined suite is pending UI integration.
- Additional test-only `fcfe564` verifies a coherent read against concurrent
  state/event and source-revision commits in the real two-connection WAL pool.
  First read stays version 0/events empty/latest revision 2; next read sees
  version 1/event 1/latest revision 3. Removing the read transaction in an
  in-memory mutation makes the test fail. Focused details/persistence: 23 passed.
- Owned disposable smoke server uses a fresh scratch Git repo/database and three
  specs. Authentication token stayed out of URLs/logs and was removed after use.
  Saved `boss-board-before.png` under the task visualization folder. The same
  pre-existing IAB MutationObserver.observe error occurred before UI changes,
  without a source URL. No matching call in app JS/bundle, LiveView JS or
  live_reload lib; an about:blank probe had no errors. Attribution remains open.
- UI source review found two asynchronous edge cases before integration: explicit
  revision → default/pinned could reuse the wrong cached source/selector, and a
  cancelled detail read could overwrite a malformed-route not-found error. Writer
  added failing regression tests and fixes before integration. Small muted labels use zinc-400 rather
  than zinc-500 for contrast against the existing dark surfaces.

- UI `0af3531` integrated: five state-derived columns, native modal, URL revision
  selection, scoped async reads, current reason and latest 50 actual events.
  Two regression cases above pass; source/selector share the desired revision and
  failure callbacks cannot overwrite closed/invalid selection. Focus returns to
  the current card. Ten new board LiveView tests plus 12 Sync tests pass.
- Browser exposed a third issue: LiveView preserves a focused SELECT's value even
  when Back updates the URL/source to the pin. Reviewed installed LiveView
  `assets/js/phoenix_live_view/dom.ts:637` and `dom_patch.ts:477`. UI followup
  `1caf934` puts desired revision on the dialog and synchronizes select value in
  the hook's `updated` callback. No change event or focus reset. Independent review
  found no blockers; browser retest confirms default pin 1 → selected 2 → Back to
  pin 1 → Forward to 2, with matching URL/source/value and select focus throughout.
- Additional UI references: xerj `showModal focus return dialog` → Agetor (MIT)
  `fbd68603afef778a618a94ca88e0c00997956afd`,
  `src/mainview/components/ui/dialog.tsx`; adopt label/Escape/focus return, reject
  custom focus trap. `kanban columns status group tasks` → weak hits followed by
  pinned Backlog App/Column reads; reject drag/drop for this read-only increment.

## Verification

- Writer: `rtk proxy asdf exec mix test test/boss_web/task_board_live_test.exs
  test/boss_web/spec_sync_live_test.exs` — 22 passed; format, compile and
  `rtk proxy node --check assets/js/app.js` passed. The original two async cases
  were observed failing before fixes. Backend mutation evidence is recorded above.
- Root combined `rtk proxy asdf exec mix test` before focused-select fix:
  159 passed / 1 skipped, seed 725982. After fix: 159 passed / 1 Linux-only skipped,
  seed 278118, 5.5 seconds. `rtk proxy asdf exec mix compile --warnings-as-errors`
  and `rtk proxy asdf exec mix format --check-formatted` passed after the fix.
  `rtk proxy asdf exec mix assets.deploy` passed after each UI integration.
- IAB on owned loopback server/fresh data: three specs yield three cards; actual
  `new` and `needs_input` state/reason/event rendered. All other state mapping is
  covered by tests, not fabricated browser states. Home shell 768 px, board
  shell 1280 px at viewport 1280; live return to Home restores 768 px.
- Keyboard Tab/Enter opens a card; native dialog is modal and background is inert.
  Escape closes and restores current card focus. Tab reaches drawer controls and
  may reach browser chrome; no background page control received focus. Board
  region takes focus and scrolls with ArrowRight. Literal `<em>` stays text.
- Browser selected revision 2 survives reload and automatic edit, explicit-ID
  rename, missing file and restore; task remains pinned to revision 1, latest is
  revision 3, card count stays three. Close/Back/Forward keep URL/content consistent.
- No page overflow at 320/768/1024/1440 px; board overflow is local. At 320 px,
  drawer width is 320 and source/form/Close remain accessible. Actual screenshots:
  `boss-task-board.png` and `boss-task-drawer.png` in
  `/Users/mpak/.codex/visualizations/2026/10/25/01a173ec-2089-7ff3-88a7-142cfa5d8f78/`.
- Existing IAB MutationObserver error remains unassigned, also observed before
  the new UI. No source URL was supplied; no clean-console claim. Other browsers
  and a Linux desktop were not checked. Full offline-edit/startup rescan evidence
  is from 003b, not a new test in this increment.
- Owned browser tab closed and viewport reset. Checked exact owned process command
  and PGID, sent SIGTERM, verified no remaining group/listener, then removed only
  the exclusively created smoke root. Existing user data/servers were untouched.
- Updated AGENTS, README, task plan/status, TASK_WORKFLOW, RESEARCH and daily log.
  BOSS_PLAN is unchanged; no dependencies, migrations or execution controls added.

## Outcome and next step

BOSS-005 implementation and verification are complete on the integration branch.
Pending local-main merge/combined checks and archival of the two writer worktrees.
Next product slice: BOSS-006 detector/capability UI. Runner reliability and positive
commit-bound run/check/review/integration evidence remain open gates.
