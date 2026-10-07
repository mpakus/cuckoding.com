# R030b — Adopt saved teams in existing scopes

Claimed on clean local main `8b4d951`; owner Codex. Acceptance is in
[the task](../tasks/R030b-scoped-team-adoption.md).

Ponytail full, architecture, workflow, LiveView, security-review and quality-gates
skills applied. Existing boards otherwise cannot use a model assigned after their
creation. Reuse immutable saved teams and command/event transactions; no new
dependency or execution mechanism.

Source references at `8b4d951`: `lib/cuckoding/team.ex:81` (confirmed, revisioned
commands), `lib/cuckoding/tabulae.ex:142` (scoped idempotent transactions),
`lib/cuckoding/planning.ex:20` (consent-bound team snapshot),
`priv/repo/migrations/20261007030000_tabula_drafts.exs:40` (immutable history).
Existing project code is Apache-2.0-licensed; no external implementation copied.

RTK proxy exceptions: exact source reads, deterministic edit/QA scripts, Mix and
native build tools where output filtering or argument rewriting changes semantics.
All shell invocations remain RTK-prefixed.

## Verification

- `rtk mix test test/cuckoding/team_assignments_test.exs test/cuckoding_web/team_adoption_live_test.exs test/cuckoding/planning_test.exs test/cuckoding_web/planning_live_test.exs`:
  17 passed. Covers confirmation, stale/default guards, competing adoption,
  command replay, foreign scope, immutable receipts, atomic event rollback,
  active/cancelling planning, old/new planning consent, draft retention, new-board
  inheritance, live updates, reconnect and expired component sessions.
- `rtk mix format` and `rtk mix compile --warnings-as-errors`: passed.
- `rtk mix quality`: final 117 tests passed; formatter, warnings-as-errors compile,
  strict Credo, Sobelow and dependency audit passed. Existing Sobelow warnings
  concern quoted keywords in Mix's generated lockfile; no findings.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r030b-target bin/dev.build`:
  final isolated bundle passed. No dependency changes. Existing OpenSSL relocation
  invalidates then replaces ad-hoc signatures as designed. Native source is
  unchanged; Rust unit/lint suites were not rerun for this Elixir-only slice.
- `rtk proxy python3 /private/tmp/cuckoding-r030b-proof-zfkx3qx1/final-smoke/verify-package.py`:
  fresh and prior-schema-copy native smoke passed with seven migrations, integrity
  `ok`, no FK violations, retained commands/teams/Arenas/boards/drafts/history and
  prior events. R040e synthetic source DB hash unchanged. No user DB was opened.
- `rtk proxy python3 /private/tmp/cuckoding-r030b-proof-zfkx3qx1/start-browser.py`
  and `connect-browser.py`: explicitly synthetic provider/model/Arena metadata,
  isolated native bundle and authenticated QA session; no provider launched.
- CUA browser: create an existing board, edit the default team in a second tab,
  inspect both rosters, reject missing consent, confirm adoption, retain unsaved
  task/brief, clear old planning consent, update column labels, save the draft;
  adopt the Arena default separately and create a board inheriting that revision.
  Current/adopted history survives rebuild/restart. Keyboard disclosure focus
  remains visible; 390×844 viewport has document/scroll widths both 390. Temporary
  viewport reset and both QA tabs closed.
- `rtk proxy python3 /private/tmp/cuckoding-r030b-proof-zfkx3qx1/snapshot-stop.py`,
  `restart-browser.py`, `connect-browser.py` and `verify-final.py`: exact command,
  team/adoption, Arena/board and draft/history retention; all prior events intact,
  only expected authorization events appended. No replay, unchanged project file,
  no active command, integrity/FKs passed, owned QA shell/BEAM/listener stopped.
- Local Markdown-path script: 104 link targets resolved. `rtk git diff --check`:
  passed. README, AGENTS and affected architecture/data/flow/security/checklist/
  developer/testing docs updated together.

The first expired-session regression caught a real shared boundary gap: parent
LiveView event hooks do not guard component-targeted events. The shared guard now
runs in both adoption and planning components with a server-supplied session ID.
Inspected installed LiveView `lifecycle.ex:97` and `channel.ex:856` to verify
component event-hook support; no new authorization mechanism was invented.
Initial Credo nesting/complexity findings were resolved by extracting the existing
command transaction pattern. Visual review caught preserved template indentation
inside role descriptions; compact inline text fixes it while preserving user
newlines. A compiler check caught a helper name conflicting with Kernel; renamed
before the final green gate. The initial QA handoff used the wrong route; the
repository's `/open` route authenticated successfully.

## Artifact and limits

Final bundle: `/private/tmp/cuckoding-r030b-target/release/bundle/macos/Cuckoding.app`.
Native SHA-256: `dcdda9d1fe9154e8896ab306e8adc41612e0d27071911f20ea85b3dd15df4fd6`.
TeamAssignments BEAM: `878374017c801cc6330943bbbff12c1db9a83a82e38881853a72f5c6ce02c854`.
TeamAdoptionComponent BEAM: `fd819e4c4e4355e6053b0a2c282a6faa7380385169fbe5e8e421c1261b9e018f`.
SessionAuth BEAM: `a29c350c1eb4545e6011d04a2e555cb2530e684d637b21421811c5b44ff71463`.
Final tested shell/BEAM `98388`/`98389`, loopback `49796`, stopped. Earlier QA
`97299`/`97302` on `49493` also stopped. User application/bundle was not replaced.
Screenshots: `/private/tmp/cuckoding-r030b-team.jpg` and
`/private/tmp/cuckoding-r030b-narrow.jpg`. Scripts/receipts/identities remain in
`/private/tmp/cuckoding-r030b-proof-zfkx3qx1/`.

This is saved-default adoption, not arbitrary per-scope editing, execution grants
or a battle. Real-account successful planning/writing, physical sleep and signed
clean-machine release gates remain open. No site change, push or deployment.
Local main integration pending.

