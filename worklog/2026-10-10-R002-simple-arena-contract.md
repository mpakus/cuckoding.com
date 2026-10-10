# R002 · Folder, tasks, Start

Claimed on clean main 2cc1ee1, feature/R002-simple-arena-contract.
Read the original eight-step story and the latest simplification. Keep reusable
agent/model/role setup, the Roman names, parallel workers and both dashboards.
Replace the mandatory Arena/Tabula/Describe setup sequence with one Arena surface.
Ponytail full 5.1.0 (MIT), workflow-and-kanban, architecture and quality-gates.
RTK proxy preserves exact source/document output. No new skill/plugin is needed.

Current source evidence: `arena_live.ex:154-224` registers a folder then links to
Open Tabulae; `tabula_live.ex:577-613,832-858` exposes checks, battle preview,
repository setup and explicit board creation. `planning_component.ex:203-327,392`
uses optional path selection and per-proposal imports. `battle_preview_live_test.exs:25`
explicitly rejects a Start battle button. These are setup/planning capabilities,
not a working one-button autonomous battle.

The user answered Docs and Arena UI together. Scope expanded to atomic default
Tabula creation in registration, suggested folder name, immediate board navigation,
Advanced disclosures and optional manual editor. Reused domain writers/components;
no migration, runtime adapter, new grant or dependency. Start remains disabled with
an explanation. Current bounded snapshots and per-proposal imports remain intact.
Elixir/LiveView and security-review skills apply; existing folder/session/consent
checks and each component's own session guard remain. No new host-side effect.


Implemented R040k's initial surface within this R002 slice: default Tabula creation
uses the existing private command writer inside registration's transaction; events
and both records roll back together. Successful registration opens the Arena. The
Arena route selects its first retained board; no mount/GET writes and no backfill
of old Arenas. Additional-board URLs and separate Arena/Tabula team controls remain.
Planning opens on empty boards; Advanced and manual editing use retained native
disclosures. Edit card opens its editor. A disabled Start explicitly says execution
and review are unavailable. Home no longer presents manual Tabula creation as setup.

Documentation: D022 records Add folder → Create tasks → Start and the separation
between bounded planning input and Start authority. Flow/UI now describe the target
rather than repeating historical click sequences; Development retains current
instructions. README/Flow/UI shrink from 6,016 to 3,810 words (37%). Technical data,
security, execution and acceptance contracts preserve immutable history and grants.
Original tasks/worklogs remain untouched. R040l/m and R050d/e remain unchecked.

Verification:
- `rtk mix test test/cuckoding/arenas_test.exs test/cuckoding_web/arena_live_test.exs test/cuckoding_web/tabula_live_test.exs test/cuckoding_web/team_adoption_live_test.exs test/cuckoding_web/planning_live_test.exs`: 26 passed.
- `rtk mix format` and final `rtk mix quality`: 187 tests passed, warning-as-error
  compilation/format passed, Credo no issues, Sobelow scan complete and audit no
  vulnerabilities reported. Earlier runs caught helper complexity/alias ordering;
  corrected before the final pass. Sobelow emitted its existing quoted-keyword
  warnings while reading Mix's lockfile.
- `rtk proxy bin/dev.build`: passed; regenerated the local Cuckoding.app. Hex's
  dependency fetch reported existing Decimal 3.1.1 advisory EEF-CVE-2026-97853 /
  GHSA-6c27-994x-c52f, despite mix audit's no-vulnerability result. Lockfile unchanged;
  dependency remediation is not claimed by this Arena slice.
- `rtk proxy bin/smoke`: passed native bundled launch, bootstrap, browser session,
  origin/replay refusal, heartbeat, graceful Quit and listener cleanup. Retained
  smoke root `/private/tmp/ccoding-smoke.RsCtPH`.
- Browser: source launcher displayed new Arenas entry UI. Automation could not
  address the native folder helper, so registration/navigation are covered by
  domain/LiveView regressions rather than claimed native click-through evidence.
  A separate `.ccoding/r002-browser` test fixture used real domain registration
  with a synthetic chooser receipt for `/private/tmp/cuckoding-r002-ui-arena`.
  No personal profiles or provider actions. Actual rendered LiveView checked at
  desktop and 390×844: default board, collapsed Advanced/manual editor, keyboard
  disclosure toggles, create/save/edit draft, card-triggered editor opening,
  persisted draft after reload. Document width 390, board viewport 300 with 1098px
  horizontal content; no page overflow. Temporary viewport reset and tab closed.
  The isolated fixture's first startup emitted a transient SQLite pool lock
  warning; it completed registration and UI checks. This is not native/provider
  acceptance or a running release claim.
- `rtk proxy python3` structural check: 17 changed/new Markdown files, 160 local
  links/headings and balanced fences passed. Exact output/source reads and this
  script use `rtk proxy` so filter formatting cannot alter parsed content.
- `rtk git diff --check`: passed. Source review traced all registration callers,
  team scope adoption and preserved component session/consent/revision guards.

No migration, new dependency, adapter/native source change, provider call, task
execution, site publication or remote push. Native Rust gates, real provider
acceptance, ten-minute onboarding and autonomous scheduling/recovery are not
claimed; unchanged native code is exercised by build/smoke only.

Handoff: implement bounded folder analysis (R040l), automatic validated card import
(R040m), then verified task execution and one Start/review loop (R050d/e). Keep
current selected-file/proposal boundaries until replacements pass their gates.
Integrate this verified slice into local main; retain fixture data, stop test
listeners and delete the merged task branch.
