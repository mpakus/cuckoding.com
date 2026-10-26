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
  not proof of a browser implementation. Concrete reference reads pending.
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

## Outcome and next step

In progress: implement and combine backend/UI, verify refresh and keyboard behavior
in a real browser, update docs, merge/test local main, then archive writer worktrees.
