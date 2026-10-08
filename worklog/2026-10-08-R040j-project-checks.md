# R040j — Saved project checks

Claimed from clean local main `6e63db4` on `feature/r040j-project-checks`.
Local main matched the saved origin/main reference at claim time; no fetch/push.
Acceptance: [task](../tasks/R040j-project-checks.md).

Ponytail full 4.13.0 (MIT), workflow-and-kanban, Elixir/LiveView, architecture,
security-review and quality-gates apply. Read current product/data/architecture/
flow/security/execution/reference contracts. Memory is historical guidance only;
the reset source and current plan determine implemented capability.

Reuse Apache-2.0 repository patterns at `6e63db4`: `lib/cuckoding/team.ex:74`
immutable saves, `lib/cuckoding/team_assignments.ex:54` idempotency/scope handling,
`lib/cuckoding_web/live/team_live.ex:92` dirty-editor refresh and `:101` explicit
reload, `lib/cuckoding/foundation.ex:486` transactional events, and
`priv/repo/migrations/20261007010000_saved_team.exs:5` append-only revisions. No third-party
implementation or dependency is needed.

Boundary decision D018: user-approved check declarations are Arena-scoped immutable
configuration, never executable agent proposals. Preview literal argv, relative
working directory and timeout; save after confirmation. No process or provider
launch, executable discovery or filesystem read occurs here. Execution/grants
remain disabled and must be verified by future Start admission.

RTK proxy exceptions: exact source reads, local editing/evidence scripts and native
packaging. Product command declarations remain unwrapped.

## Implementation

Added an Arena-specific Project checks page, linked from Arena/Tabula settings.
Users edit a bounded set, preview exact normalized argv/directory/timeout, then
confirm. Every content edit discards preview/consent. Live changes preserve draft
text/errors and clear stale approval. Foreign/stale recovered forms remain blocked
until explicit reload; the browser cannot silently replace their base revision.
Reload asks before discarding edits. Names and arguments render as escaped text.

The eighth forward-only migration adds append-only `check_revisions`, with Arena
and command references, unique consecutive per-Arena revisions and triggers against
updates/deletion/skipped revisions. Existing Arenas start with no declarations.
`save_checks` commits a completed/rejected command and public event atomically with
the revision. Idempotent keys retain their original outcome. History never enters
the dispatcher or changes provider/workspace state. No dependency or native source
was added. Definitions explicitly retain `execution: disabled`; structure validation
is not executable discovery, command-safety analysis or runtime enforcement.

## Verification

- `rtk mix format` and `rtk mix compile --warnings-as-errors`: passed.
- `rtk mix test test/cuckoding/project_checks_test.exs test/cuckoding_web/project_checks_live_test.exs`:
  7 passed, including the final tighter sequence-trigger and Arena-link assertions.
  Initial run stopped at a missing fixture import in the test module; fixed the
  import before any test result was claimed.
- `rtk mix quality`: 150 tests passed; formatter, warnings-as-errors compiler,
  strict Credo, Sobelow and dependency audit passed. First full run passed tests
  but Credo flagged one complex validator; named the existing executable/name
  predicates and reran successfully. Known Sobelow Elixir 1.20 lockfile quoted-key
  warnings remain tool diagnostics; no vulnerabilities or new analysis exclusions.
- Coverage includes immutable/scoped revisions, exact replay/key conflict, racing
  writers, stale/missing scope, explicit removals, atomic rollback on audit failure,
  closed schema/bounds/controls/path traversal/RTK refusal, literal shell-looking
  arguments, disabled execution, escaped previews, consent invalidation, retained
  dirty forms, reload confirmation, reconnect, forged digest and expired sessions.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r040j-target bin/dev.build`:
  passed. Existing Tailwind signature replacement and OpenSSL relocation/re-sign
  diagnostics; separate target preserved other bundles. No native source changed,
  so Rust unit/lint gates were not repeated. Native compile/package and smoke ran.
- `rtk proxy python3 /private/tmp/cuckoding-r040j-proof-zj2qrxl_/verify-package.py`:
  fresh and copied-prior packaged smoke passed: native bootstrap, browser session,
  replay/origin refusal, heartbeat, graceful shell Quit and listener cleanup.
  Fresh/upgrade roots had eight migrations, SQLite integrity `ok`, no FK violations
  and zero inferred check approvals. Prior commands/events/teams/Arenas/boards/
  drafts/revisions/adoptions and both Markdown files were preserved. Original stopped
  R040i source DB was unchanged, SHA-256
  `e390e1be6f48e7610b9df041ee87a93bce46e296cf8e803fce276392355f38f2`.
- An isolated `rtk proxy python3` downgrade check copied the migrated fresh DB and
  ran the previous R040i bundle smoke: exit 1, migration rows/integrity/FKs preserved.
  The old shell reports only a generic startup failure; its existing unknown-schema
  guard explains the expected refusal, not a richer UI diagnosis. No live root was
  downgraded. Prior backup remained untouched.

## Packaged UI and restart evidence

QA root: `/private/tmp/cuckoding-r040j-proof-zj2qrxl_`. Copied prior fixtures contain
synthetic team metadata and no credentials. No provider or saved check was executed.
The first browser client refused both supported local origins before loading,
although the owned loopback listener existed. Browser access recovered following
the independently required controlled restart; no product/security setting changed.

- `rtk proxy env MIX_ENV=test mix run --no-start /private/tmp/cuckoding-r040j-proof-zj2qrxl_/seed-checks.exs`:
  while the QA app was stopped, called public domain APIs on the copied DB, refused
  unconfirmed input and saved two immutable revisions. This was programmatic
  fixture setup, not claimed UI evidence. Initial script used a nonexistent
  PubSub.start_link; corrected it to the repository's supervised child-spec pattern.
- `rtk proxy python3 /private/tmp/cuckoding-r040j-proof-zj2qrxl_/start-browser.py`
  and `rtk proxy python3 /private/tmp/cuckoding-r040j-proof-zj2qrxl_/connect-browser.py`:
  launched the selected bundle and authenticated with a test-only handoff. One
  immediate listener lookup preceded readiness; the later lookup passed.
- CUA followed Arenas → Open Tabulae → Project checks, opened the editor with
  Enter, changed timeout 120→180, previewed exact argv, refused Save without consent,
  then confirmed revision 3. Added Format check and confirmed two-check revision 4.
  Changed an unsaved name, verified Reload asked first and Keep editing preserved it,
  then explicitly discarded the draft. Editor disclosures stayed open through saves.
  Keyboard history focus remained visible. Desktop 1280×900 and narrow 390×844
  were visually checked; narrow document scroll width was exactly 390px.
- `rtk proxy python3 /private/tmp/cuckoding-r040j-proof-zj2qrxl_/snapshot.py`:
  all four revisions with exact argv/timeouts, disabled execution, idle ledger,
  unchanged Arena source/canary files and integrity/FKs passed.
- `rtk proxy python3 /private/tmp/cuckoding-r040j-proof-zj2qrxl_/verify-restart.py`:
  all persisted check/command/task/team/board/adoption rows and both Markdown hashes
  survived restart; startup events only appended. Browser reopened revision 4 with
  both checks and the exact saved timeouts. No check/provider request replayed.
- `rtk proxy python3 /private/tmp/cuckoding-r040j-proof-zj2qrxl_/stop.py`:
  validated owned executable/parent identity, sent BEAM SIGTERM, observed shell
  heartbeat exit and closed listener. Shell/BEAM/port: `27827/27848/52196`,
  `29798/29799/53017`, `30615/30624/53439`. All stopped. This persistence drill is
  controlled service exit, not a tray-menu Quit claim; real shell Quit is covered
  separately by both packaged smoke runs.
- Screenshots: `/private/tmp/cuckoding-r040j-desktop.jpg` and
  `/private/tmp/cuckoding-r040j-mobile.jpg`. Temporary tab closed, viewport reset.

Tested bundle: `/private/tmp/cuckoding-r040j-target/release/bundle/macos/Cuckoding.app`.
Native SHA-256 `8ad7026b61dbf8c1b8db823b306c9aeb22a168701937a257ea10ac98a5cac04e`;
ProjectChecks BEAM `2527518e0c037059901b82684ffe03277e6056ebdedaabe8b272bf00f282ec26`;
CheckRevision BEAM `44e1fb26f0a09ee594ae38d2db28715398e47e29a34a96017806860db08ede5e`;
ProjectChecksLive BEAM `bb322f5986b70728996570c38dec4a9e070f10c043c4a6621f6af0a47d2ead86`.
Identity metadata is retained in the QA root. No QA app is left running.

Packaging/restart checks followed local-runner and menubar-shell ownership rules.
No task processes, ports allocator, scheduler, runtime grant or power logic changed;
scheduler fairness, simulated/physical sleep, active-battle Quit and clean-machine
release gates were not run or claimed. Real provider, host-check execution and
battle orchestration remain open. No push, Pages deployment or public release.
README, AGENTS and docs now distinguish saved checks from authority to execute.

`rtk proxy python3 /private/tmp/cuckoding-r040j-proof-zj2qrxl_/check-docs.py`:
104 local Markdown link targets passed. `rtk git diff --check`: passed. The first
diff check found one extra EOF blank in DECISIONS.md; `rtk proxy git diff --check`
exposed the exact diagnostic and it was fixed before the passing check.

## Local integration

Implementation commit `6a83d06` (`feat(checks): save confirmed Arena verification
declarations`) was fast-forwarded into local main with `rtk git switch main` and
`rtk git merge --ff-only feature/r040j-project-checks`.
`rtk git branch -d feature/r040j-project-checks` deleted the merged feature branch.
`rtk git status --short --branch` was clean, one commit ahead of saved origin/main
before this task/worklog closeout. No push performed. The tested package contains
the same implementation; this closeout changes only task and worklog status.
