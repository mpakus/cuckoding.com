# Worklog — 1008 helpful user-facing messages

## Acceptance criteria

Audit and improve all Phoenix UI errors, statuses, and empty states as defined in `tasks/phase-10-hardening-beta/1008-helpful-ui-messages.md`.

## Baseline

- Resumed from `72fac12` on `fix/1008-helpful-ui-messages`, preserving the
  unrelated untracked `icon.png`.
- Loaded Ponytail 4.10.0 full (MIT), Better Writing, LiveView,
  security-review, and quality-gate guidance. Ponytail selected one bounded
  formatter plus existing native LiveView alert/status regions; no dependency
  or message framework was added.
- XERJ project search was attempted first but no node was reachable at
  `localhost:9200`; direct repository source inspection was used and no peer
  code was adapted.

## Inventory and implementation

- Inspected all 14 files in `lib/cuckoding_web/live/`, the shared layout flash,
  and the knowledge retrieval controller. Nine LiveView files own dynamic error
  alerts; thirteen own status/notice regions. Closed state labels and the
  machine knowledge API's documented error codes remain explicit mappings.
- Added `CuckodingWeb.PublicError` for bounded application-owned changeset
  messages and fixed unexpected-failure recovery copy. It never receives the
  unexpected reason and never renders submitted values.
- Removed every `inspect/1`, raw tuple/atom fallback, changeset dump, and adapter
  error-code interpolation from browser LiveViews. Git/worktree errors retain
  their existing non-destructive commit/stash guidance. Run and release failures
  point to durable timeline, findings, logs, or evidence.
- Updated task, project, board, planning, agent authorization, plugin, knowledge,
  proposal import, release, and run-preparation copy. Empty states now identify
  the next action or explain which durable event populates the view. Removed the
  stale “after Phase 7” run copy and linked to the shipped Knowledge surface.
- Updated `UI_DASHBOARD`, `SECURITY`, `TESTING`, `DOCUMENTATION_AUDIT`,
  `AGENT_AUTHORIZATION_FLOW`, and `PLAN`. The flow audit now reflects task 1019
  while preserving real-provider, workflow-loop, beta, and release gates.

## Verification

- `rtk env -u CR_PAT mix test` focused LiveView/public-message set — 25 tests,
  zero failures (seed 199100) after updating one expected rejection phrase.
- `rtk env -u CR_PAT mix test test/cuckoding_web/agent_floor_live_test.exs
  test/cuckoding_web/public_error_test.exs` — 12 tests, zero failures (seed
  464773) after replacing a stale Phase 7 expectation.
- First `rtk env -u CR_PAT mix quality` found only that stale test expectation;
  all static/security stages still passed. After correcting the expectation,
  final `rtk env -u CR_PAT mix quality` passed with seed 844588: 259 tests,
  10 properties, zero failures; warnings-as-errors compilation, unused
  dependencies, Credo (203 files, 3237 mods/functions), Sobelow, and Hex audit
  passed. Expected crash-worker fixture logs appeared during the passing suite.
- `rtk git diff --check` — passed.
- Browser verification on `/knowledge` showed the revised candidate empty state
  in the accessibility tree. Existing browser console output still contains the
  previously observed MutationObserver non-Node error without a source URL; no
  JavaScript changed, so clean-console acceptance is not claimed here.
- Static regression scans every LiveView and fails on `inspect(`. Repository
  search found no remaining raw reason/code interpolation in `lib/cuckoding_web`.
