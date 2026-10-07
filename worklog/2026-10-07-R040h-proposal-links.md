# R040h — Speculator proposal links

Claimed by Codex on `feature/r040h-proposal-links`, from clean `e40c0bb`
(16 commits ahead of saved origin/main). Acceptance:
[task](../tasks/R040h-proposal-links.md). No remote publication.

Ponytail full 4.13.0 (MIT), workflow, architecture, LiveView, agent-adapter,
security-review and quality-gates applied. Read the core product contracts.
Reuse Apache-2.0 source at `e40c0bb`: `lib/cuckoding/planning.ex:202` closed response
validation, `lib/cuckoding/tabulae.ex:140` immediate import/save transaction,
`lib/cuckoding_web/live/planning_component.ex:378` source disclosures and
`desktop/src-tauri/src/connection/model_check.rs:127` existing outputSchema transport.
No new external API, dependency, graph framework or table is required.

New `brief-plan-v2` tasks use bounded indices into the same ordered proposal and
its frozen document array. Prerequisites must precede their dependents, making
cycles unrepresentable without a forward/self-reference that is rejected. Import
resolves indices through completed same-board import commands; missing imports
require adding the prerequisite first. Source citations reference exact stored
snapshots; they do not assert semantic correctness or live file freshness.

RTK proxy exceptions: exact source reads, editing/QA scripts, structured output
and native packaging. Product commands remain unchanged/unwrapped.

## Verification

- `rtk mix test test/cuckoding/planning_test.exs test/cuckoding/tabulae_test.exs test/cuckoding_web/planning_live_test.exs test/cuckoding/planning_documents_test.exs`
  passed 25 focused tests during implementation.
- `rtk mix test test/cuckoding/planning_test.exs` passed 9 after malformed-reference,
  legacy and transaction rollback additions; the later six-task/four-source bounds
  check is included in the full gate below.
- `rtk mix quality` final pass: 135 tests, formatter, warnings-as-errors compile,
  strict Credo, Sobelow and dependency audit. The first full run passed 134 tests
  but Credo found a duplicate SQL alias and a complex refresh function; fixed by
  removing the alias and sharing the existing editing predicate. Final gate clean.
  Sobelow still reports the documented Elixir 1.20 lockfile parser diagnostics.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`: 34 passed.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`: passed.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`: passed.
- `rtk proxy python3 /private/tmp/cuckoding-r040h-proof-1zqyut2c/check-docs.py`:
  95 local Markdown link targets passed. `rtk git diff --check`: passed.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r040h-target bin/dev.build`:
  passed; existing Tailwind re-sign and OpenSSL relocation/re-sign diagnostics.
  Isolated target did not overwrite the default bundle.
- `rtk proxy python3 /private/tmp/cuckoding-r040h-proof-1zqyut2c/verify-package.py`:
  fresh and copied-prior packaged smoke passed: native launch/bootstrap/browser
  cookie, replay/origin refusal, heartbeat, graceful shell Quit and listener
  cleanup. Seven migrations, SQLite integrity/FKs and existing commands/events,
  teams/Arenas/boards/drafts/revisions/adoptions preserved. Prior source was the
  stopped R040f fixture containing v1 receipts; original DB unchanged, SHA-256
  `c6506e13f480c3b2d4f8e7fa22f46b629d45c2a477ace88988b59f125eb4b986`.

Regression coverage binds v2 to the actual selected snapshots and rejects malformed,
duplicate, unsent, self, forward/cyclic and downgraded references without retaining
provider text. It covers v1 receipts, model matching, frozen native schema/grants,
same-board ordered imports, command-key replay, preserved prerequisite edits, event
rollback, citation provenance after edits/reconnect and expired-session refusal.
The malformed-dependency cases use empty citations so another validation failure
cannot hide a missed dependency check. Completion events expose counts only.

## Packaged browser and restart proof

QA root: `/private/tmp/cuckoding-r040h-proof-1zqyut2c`. The isolated fresh data root
uses a clearly labeled synthetic executable/catalog/team, with no real account.
CUA drove the packaged browser UI: create board, preview `docs/plan.md`, consent
to the fixture turn, refuse dependent-first import, import both in order, inspect
the resolved prerequisite, edit the dependent title and reopen original citations.
The fixture asserts the v2 schema and reference instructions reached native
`turn/start`; only the selected snapshot was sent. Its 70-byte text/hash matched
the editor before and after restart. The unselected canary/project files stayed
unchanged. Unsaved manual text survived imports, and the discard guard appeared
before switching editors. Enter opened both native source disclosures; focus
remained on the summary. At 390×844, document scroll width was exactly 390px.

- `rtk proxy python3 /private/tmp/cuckoding-r040h-proof-1zqyut2c/snapshot.py`:
  dependency/source/import/integrity/idle assertions passed; saved all durable rows.
  An initial QA query used `plan_brief`; corrected to the existing `plan_tabula`
  command kind before the passing run. This was a QA-script correction only.
- `rtk proxy python3 /private/tmp/cuckoding-r040h-proof-1zqyut2c/stop.py`:
  validated owned child/executable identity, sent BEAM SIGTERM, then confirmed
  shell heartbeat exit and closed listener. First shell/BEAM `36075/36076`, port
  `54581`; after restart `45530/45531`, port `54930`. Both stopped. Native CUA
  app selection timed out; this browser persistence check used controlled service
  exit, not a claimed tray-menu Quit. Graceful shell Quit is separately covered by
  both packaged smoke runs above.
- `rtk proxy python3 /private/tmp/cuckoding-r040h-proof-1zqyut2c/restart-browser.py`
  and `rtk proxy python3 /private/tmp/cuckoding-r040h-proof-1zqyut2c/connect-browser.py`:
  relaunched the same bundle and authenticated with an isolated test handoff.
- `rtk proxy python3 /private/tmp/cuckoding-r040h-proof-1zqyut2c/verify-restart.py`:
  all saved commands, task revisions/dependencies, teams/boards/adoptions and prior
  events unchanged (startup events append). Browser reopened edited revision 2
  with the original proposal ID and source text/hash. No provider turn replayed.
- Screenshots: `/private/tmp/cuckoding-r040h-desktop.jpg` and
  `/private/tmp/cuckoding-r040h-mobile.jpg`. Temporary tab closed and viewport reset.

Tested bundle: `/private/tmp/cuckoding-r040h-target/release/bundle/macos/Cuckoding.app`.
Native SHA-256 `8ad7026b61dbf8c1b8db823b306c9aeb22a168701937a257ea10ac98a5cac04e`;
Planning BEAM `b43dd71da9676367141ff6ce487e23e9f76fb918b2f6e78dad879d5992e4111b`;
Tabulae BEAM `9a1b77ca447bb2068236b89135c3942c1084b21084f329afc734a6a2c4d45391`.
The QA root's `identity.json` retains all five changed BEAM hashes.

No real-provider acceptance, battle execution, physical sleep/wake, clean-machine
installation, signing/notarization, remote publication or Pages deployment claimed.
No migration/dependency added. README, AGENTS and affected docs describe shipped
planning separately from accepted specs and execution.

## Local integration

Implementation commit `ffe58e9` (`feat(planning): preserve proposal prerequisites
and source citations`) was fast-forwarded into local main with
`rtk git switch main` and `rtk git merge --ff-only feature/r040h-proposal-links`.
`rtk git branch -d feature/r040h-proposal-links` removed the merged branch.
`rtk git status --short --branch` was clean, main 17 commits ahead of the saved
origin/main reference before this documentation closeout. No push performed.
The packaged evidence above is the same implementation; this closeout changes
task/worklog status only.
