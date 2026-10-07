# R040b — Tabula drafts

Claimed on clean local main `c896da7`; branch `feature/R040b-tabula-drafts`.
Acceptance: multiple Arena-scoped boards inheriting its team; revisioned manual
tasks with Specs/ToDo controls, readiness validation, stale/scope/idempotence
guards; no execution or project writes; browser/migration checks and local merge.

Ponytail full, LiveView, workflow-and-kanban, quality-gates and security/local
runner guidance applied. Reused this checkout's command transaction/event pattern
(`lib/cuckoding/team.ex:92`), immutable revisions
(`priv/repo/migrations/20261007010000_saved_team.exs:31`) and Arena LiveView
(`lib/cuckoding_web/live/arena_live.ex:10`) at `c896da7`. No external source or
dependency adapted. Arena team identity is frozen; configuration does not grant
host access or bypass independent review. No peer implementation needed.

RTK proxy exceptions: exact multiline scripts/fixture inspection, package build
and smoke harness require unfiltered output/environment/exit semantics. Product
commands remain unwrapped.

## Delivered

- Multiple Arena-scoped Tabulae, immutable version-1 default columns, inherited
  Arena team reference and visible role names. No new grants or provider calls.
- Bounded manual task content, stable task UUIDs, current projections and immutable
  revisions. Completed/rejected commands and events commit together before PubSub.
  Replay returns the original receipt, including after subsequent task edits.
- Specs/ToDo movement through labelled native controls; ToDo needs description and
  criteria. Application and SQLite gates refuse delivery stages. Foreign scope,
  stale revision, conflicting key and recovered-form guards prevent overwrites.
- Two-region board/editor UI, task history, dirty-text/error preservation and
  explicit unsaved-discard confirmation. Project files remain untouched.
- Updated README, AGENTS, architecture/data/flow/UI/development/testing contracts
  and the R040 checklist. Full planning/execution criteria remain unchecked.

## Verification

- `rtk mix format` — passed.
- `rtk mix compile --warnings-as-errors` — initially caught an unused alias;
  removed it; the final quality run's compiler passed.
- `rtk mix test test/cuckoding/tabulae_test.exs test/cuckoding_web/tabula_live_test.exs`
  — initial run 9/11 passed; corrected two test harness calls (redirect result and
  LiveView unused-field metadata). All 11 pass in the final suite.
- `rtk mix quality` — final **85 tests passed**, format and warnings-as-errors
  compilation passed, Credo no findings, Sobelow completed, dependency audit no
  vulnerabilities. An earlier Credo run requested a simpler stage-validation
  function and SQL aliases; both fixed. Existing Sobelow quoted-keyword lockfile
  warnings are tool diagnostics, not compiler failures.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r040b-target bin/dev.build`
  — passed, including assets, production release and macOS bundle. Isolated target
  preserves the user's older running bundle. No Rust source/dependency changes;
  unchanged Rust tests/lints were not rerun in this slice.
- `rtk proxy python3 /private/tmp/cuckoding-r040b-proof-xpugkbwm/verify-package.py`
  — fresh and copied-R040a packaged `--smoke-test` passed. Six migrations, SQLite
  integrity and foreign keys passed; prior team/Arena rows retained exactly and
  source database hash unchanged. Native smoke covers bootstrap/handoff/replay,
  foreign origin, heartbeat and graceful Quit/listener cleanup.
- CUA browser checks against the packaged release at **127.0.0.1:49452**:
  create two independent boards; reject incomplete ToDo without losing text;
  save/move/reload task; inspect immutable history; keep/discard unsaved edits;
  move Specs → ToDo using native **Space / ArrowDown / Enter**, then keyboard Save.
  Desktop capture and 390×780 layout inspected. At narrow width, document client/
  scroll widths both **390px**; the board's **1098px** content scrolls within its
  **300px** region. The End key did not change horizontal scroll; this is not
  recorded as a passing keyboard-scroll check. Column movement itself passed.
- Browser authentication used a one-minute test-only handoff inserted into the
  isolated fixture DB. Native authentication was independently covered by smoke;
  this is not real-provider evidence or a product authentication bypass.
- `rtk proxy python3 -` cleanup/restart harness — verified owned shell **3096** /
  release **3100**, signalled only that release with SIGTERM and observed native
  heartbeat exit. Listener **49452** closed. A subsequent packaged smoke/Quit
  retained **2 boards, 1 task, 4 revisions**, with integrity/FKs and source hash
  unchanged. UI-test cleanup used the documented release signal, not a tray click.
  All test instances stopped; no unrelated application was signalled.
- `rtk proxy python3 -` local Markdown link checker — **22 documents passed**.
  `rtk git diff --check` — passed.

## Artifact and limits

Tested bundle: `/private/tmp/cuckoding-r040b-target/release/bundle/macos/Cuckoding.app`.
Evidence root: `/private/tmp/cuckoding-r040b-proof-xpugkbwm` (smoke/restart logs,
prior-schema copy, fixture state, smoke harness and `identity.json`).

SHA-256:

- Native executable: `e89a134920955067b71f016be14c62a597bf6fb7002e04ded67cf70e12a94169`
- Tabulae BEAM: `b60335de19bd60419b12e7d22d0b301446657dd77f456b31038be78e480c74b9`
- TabulaLive BEAM: `1119f2a1638e3920315793bf060aeb174231a7267f7bf3a7fa2054c003b91f3b`
- Prior source DB: `bf14debc4e4b08e788cde8e0e8b981fe4f34c0b5878cd30da3896dded0a56d34`

Screenshots: `/private/tmp/cuckoding-r040b-tabula-desktop.jpg` and
`/private/tmp/cuckoding-r040b-tabula-narrow.jpg`. Saved task prose is synthetic QA
content. The copied Arena points at an existing folder, which was not read or
modified during this slice. Manual planning needs no filesystem access.

No real-provider, clean-machine, signing, sleep/wake or autonomous battle claim.
No push, Pages deployment or replacement of the user's running app. Next R040
work: Git validation/consented initialization and baseline commit, then agent
planning/provenance, dependencies and custom workflow definitions.

## Local integration

`9092f8d` — `feat(tabulae): Add inherited boards and revisioned task drafts`.
`rtk git switch main` and `rtk git merge --ff-only feature/R040b-tabula-drafts`
passed; `rtk git branch -d feature/R040b-tabula-drafts` removed the merged branch.
The tested application bytes are unchanged by this integration-record update.
Local integration only; no remote publication or deployment.
