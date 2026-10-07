# R040g — Task prerequisites

Claimed by Codex on `feature/r040g-task-prerequisites` from clean main `160049e`
(14 commits ahead of saved origin/main). Acceptance is in
[R040g](../tasks/R040g-task-prerequisites.md). No remote publication.

## Approach and references

Ponytail full 4.13.0 (MIT), workflow, LiveView and quality-gate skills applied.
Read product, architecture, DB, flow, security and execution contracts. Reuse
repository source at `160049e` (Apache-2.0): `lib/cuckoding/tabulae.ex:70,128,260`
save/import transaction, `lib/cuckoding/records.ex:122` immutable draft revisions
and `lib/cuckoding_web/live/tabula_live.ex:331,348` guarded editors/history.
No external graph library, worker or new dependency table is
needed: the current revision's JSON already stores complete draft intent.

An immediate transaction validates references and traverses the current graph
before appending the next revision. It cannot race another writer into a cycle.
SQLite remains authoritative; a virtual projection exposes the selected revision's
IDs. Missing fields in prior revisions mean no prerequisites. Omitted fields in
legacy save requests preserve current edges; explicit empty lists remove them.
These relationships are planning only, not a completion or execution grant.

`rtk proxy` exceptions: exact source/docs reads, editing/verification scripts and
native packaging require unfiltered output/exit semantics. No stored product
command changes.

## Verification

- `rtk proxy mix format lib/cuckoding/{records,tabulae}.ex lib/cuckoding_web/live/tabula_live.ex`
  and focused changed-test formatting: passed. Final formatting is also in quality.
- `rtk proxy mix test test/cuckoding/tabulae_test.exs test/cuckoding_web/tabula_live_test.exs test/cuckoding/planning_test.exs`:
  initial 16 existing tests passed; after additions, 22/23 passed. The failing UI
  fixture used an empty map/nil which form encoding omits/converts to the valid
  empty sentinel. Corrected it to malformed values that survive wire encoding;
  domain tests still cover nil/maps directly. All pass in the final full suite.
- `rtk mix quality`: final **129 tests passed**, formatter and warnings-as-errors
  compilation passed, strict Credo clean, Sobelow completed and dependency audit
  found no vulnerabilities. Earlier Credo identified input-handler complexity;
  extracted the small form-bound check and reran. Sobelow emits the already
  documented Elixir 1.20 quoted-keyword diagnostics for `mix.lock`.
- Coverage includes diamond/chain graphs, latest-other-task cycles, self/missing/
  foreign links, 16/17 bounds, malformed/duplicate UUIDs, old receipts and missing
  fields, omission versus explicit clear, import defaults, stable rejected-key
  replay, stale tasks, atomic event rollback with no broadcast, dirty forms and
  reconnect/history. No delivery command is admitted.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r040g-target bin/dev.build`:
  passed for initial browser QA. Browser inspection found Save lost focus when
  the error paragraph appeared; a stable button ID fixes its DOM identity.
  Final `rtk mix quality` above includes this correction.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r040g-final-target bin/dev.build`:
  passed. These isolated targets preserve the default bundle. Existing OpenSSL
  relocation/signature warnings are followed by the build's local re-signing.

Retained QA root: `/private/tmp/cuckoding-r040g-proof-7bubbza6`.
All scripts below ran via `rtk proxy python3 <absolute-path>`:

- `verify-package.py`, then `final-smoke/verify-package.py`: both builds passed
  fresh and copied-prior native smoke, seven migrations, integrity and foreign
  keys. Final prior source was the stopped R040f fixture DB; all command, event,
  team, Arena, board, draft/revision and adoption rows stayed identical, except
  appended startup events. Source SHA-256 stayed
  `c6506e13f480c3b2d4f8e7fa22f46b629d45c2a477ace88988b59f125eb4b986`.
- `start-browser.py`, `connect-browser.py`, `snapshot-stop.py`,
  `restart-browser.py`, `connect-browser.py`, `verify-restart.py`, then final
  `snapshot-stop.py`: passed. Fixture metadata was seeded in the fresh private DB;
  board/tasks/links were created through the authenticated UI, with no provider.
  Restart preserved all saved graph/history/commands and prior events.
  `initial-before-restart.json` retains the comparison snapshot.
- CUA browser checks: create board/tasks; Space to select prerequisites; save to
  ToDo; card labels; cycle refusal with checkbox retained; correct/remove selection;
  reopen history after restart. Final error submission via Enter retained focus
  on `draft-save`. At 390×844, document width was 390 with no page overflow;
  Tab moved from the checkbox to Save. Another editor's save preserved unsaved
  title, checked prerequisite, open history and title-field focus in the first tab.
  Viewport reset and both QA tabs closed.
- Screenshots: `/private/tmp/cuckoding-r040g-desktop.jpg` and
  `/private/tmp/cuckoding-r040g-narrow.jpg`, from the final build.
- Initial owned shell/BEAM `19372/19373`, listener `52855`; final
  `22086/22087`, listener `53067`. Both gracefully stopped after executable/parent
  ownership checks; shell exit and closed listener verified. These are historical
  QA identities, not a currently running app. Project canary stayed unchanged.

Final bundle: `/private/tmp/cuckoding-r040g-final-target/release/bundle/macos/Cuckoding.app`.
`final-smoke/identity.json` records native and BEAM SHA-256 values. Native:
`2326f13a70d9bb619f50c7adc7e9ee3c85a986add1cd719841fa36022cd114b1`;
Tabulae: `dad1fd4d0b2a804b60fb292017ec05950029f61ac129dd31cd79b1fd594e7f72`;
TabulaLive: `3f888210b6e171d7ae4f50e524ad92fbc9f973a4fe416b3f50173f91e60f9994`.

No Rust source, transport, permissions, process lifecycle or migration changed;
Rust lint/unit gates were not rerun. Clean-machine install, real provider turns,
sleep/fair scheduling and execution acceptance remain open, not fixture passes.
No public site edits/deployment or default installed/running bundle replacement.

`rtk proxy python3 /private/tmp/cuckoding-r040g-proof-7bubbza6/check-docs.py`:
91 local Markdown link targets passed. Source/claim review and
`rtk git diff --check` passed.
Local main integration: `1184a43` fast-forwarded with
`rtk git switch main` and `rtk git merge --ff-only feature/r040g-task-prerequisites`;
`rtk git branch -d feature/r040g-task-prerequisites` removed the merged branch.
`rtk git status --short --branch` confirmed clean main, 15 commits ahead of the
saved remote reference before this documentation closeout. No push or deployment.
Remaining work includes accepted Markdown specs,
provider-proposed dependencies, custom columns/role grants and battle execution.
