# R040i — Accepted Markdown specifications

Claimed from clean local main `3a50c48` on `feature/r040i-accepted-specs` (18 commits
ahead of saved origin/main). Acceptance: [task](../tasks/R040i-accepted-specifications.md).

Ponytail full 4.13.0 (MIT), workflow, LiveView, architecture, security-review and
quality-gates apply. Read product/architecture/data/flow/security/execution and
reference-coding contracts. Reuse the Apache-2.0 command/claim/event boundary,
draft history transaction, private storage guards and session-protected controller
pattern already in this repository; no provider API or dependency is added.

Decision: command receipts own immutable spec snapshots and artifact identity.
Write one bounded app-owned Markdown file per acceptance command outside the DB
transaction, then revalidate its bytes and the current task/prerequisite revisions
before committing acceptance/history/ToDo together. Uncertain writes stay retained
and do not replay. No new general artifact framework or table is needed.

RTK proxy exceptions: exact source/document reads, local editing/QA scripts,
structured evidence and native packaging. Product commands remain unwrapped.

## Implementation and reference reuse

At base `3a50c48`, reused `lib/cuckoding/foundation.ex:314` claims/no-replay,
`:408` completion dispatch and `:480` append-before-broadcast events;
`lib/cuckoding/tabulae.ex:173` immediate transactions and `:336` immutable draft
writes; `lib/cuckoding/storage.ex:8` private data preparation and `:100` path
guards; `lib/cuckoding_web/controllers/session_controller.ex:27` protected
controller handling. These are Apache-2.0 repository sources. No external
implementation was copied; the existing app-owned storage boundary applies.

The accepted command freezes exact Markdown, source citations and task/prerequisite
revisions. Its UUID names an exclusively created private file. Completion verifies
bytes/hash, current revisions and the claim before atomically recording the receipt,
ToDo revision and events. Pending/uncertain writes are never replayed or overwritten.
Historical receipts remain readable; canonical textual UUIDs prevent binary aliases
from reaching download names. The UI preserves dirty text and disclosures, clears
stale consent, offers cancel/inspect and requires a live browser session.

## Verification

- `rtk mix format` and `rtk mix compile --warnings-as-errors`: passed.
- `rtk mix test test/cuckoding/specifications_test.exs`: 5 passed after fixing the
  test fixture to restore the optional original data-directory configuration.
- `rtk mix test test/cuckoding/specifications_test.exs test/cuckoding_web/specification_live_test.exs`:
  8 passed. The initial LiveView check tried submitting a deliberately disabled
  confirmation field; corrected the test to inject event parameters and exercise
  the expired-session guard. No product behavior was relaxed.
- `rtk mix quality`: final pass, **143 tests**, formatter, warnings-as-errors compile,
  strict Credo, Sobelow and dependency audit. First full run passed the tests but
  Credo flagged a redundant `with` and nested validation/request code; simplified
  those before the passing runs. Final run includes canonical UUID alias rejection.
  Sobelow emits the known Elixir 1.20 quoted-lockfile-key diagnostics; no security
  findings or dependency vulnerabilities. The two new scoped traversal exclusions
  cover only validated app-owned UUID paths and are explained in SECURITY.md.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r040i-target bin/dev.build`:
  passed, including a final rebuild after UUID hardening. Existing Tailwind re-sign
  and OpenSSL relocation/re-sign diagnostics; default bundle was not replaced.
- `rtk proxy python3 /private/tmp/cuckoding-r040i-proof-5llneac_/verify-package.py`
  and final `rtk proxy python3 /private/tmp/cuckoding-r040i-proof-5llneac_/verify-final-package.py`:
  fresh and copied-prior packaged smoke passed. Native launch/bootstrap, browser
  cookie, replay/origin refusal, heartbeat, graceful shell Quit and listener cleanup
  passed. Seven migrations, integrity/FKs and prior commands/events/teams/Arenas/
  boards/drafts/revisions/adoptions preserved. Prior source was stopped R040h data;
  its original DB remained unchanged, SHA-256
  `89a47bc0525f9b81653e0dd6cedd91aeeb47f1192387d80f1996d3d45a2bafe1`.

Focused cases cover exact intent before I/O, consent, idempotency/key conflicts,
revision staleness, task/prerequisite changes, rollback when the completion event
fails, cancellation/expired claims, no replay, literal fenced source text, path
traversal, overwrite, symlinks/hardlinks, size limits, tampered bytes, authenticated
attachment downloads and expired component sessions. Acceptance does not alter
the workspace/team revision or expose descriptions in audit events.

## Packaged browser and restart proof

QA root: `/private/tmp/cuckoding-r040i-proof-5llneac_`. The copied prior fixture has
a clearly synthetic team and two linked drafts. No provider was invoked. CUA drove
the packaged UI to preview exact Markdown, refuse missing consent, accept the
dependent task and download its original file. Editing its prerequisite marked
that acceptance historical. Reacceptance saved a new file and ToDo revision 4;
the original remained intact. Keyboard disclosures and focus worked. At 390×844,
document scroll width was exactly 390px; the desktop view was checked at 1280×900.

- `rtk proxy python3 /private/tmp/cuckoding-r040i-proof-5llneac_/snapshot.py`:
  two accepted commands, exact task/dependency revisions, file bytes/hashes/modes,
  download equality, SQLite integrity and idle-state assertions passed.
- `rtk proxy python3 /private/tmp/cuckoding-r040i-proof-5llneac_/stop.py`:
  verified owned child/executable identity, sent BEAM SIGTERM, then confirmed shell
  heartbeat exit and closed listener. First shell/BEAM `68150/68151`, port `56752`;
  restart `68755/68756`, port `56920`; final build `70078/70083`, port `57255`.
  All stopped. This controlled service-exit check is not a tray-menu Quit claim;
  graceful shell Quit is separately covered by packaged smoke above.
- `rtk proxy python3 /private/tmp/cuckoding-r040i-proof-5llneac_/restart-browser.py`
  and `rtk proxy python3 /private/tmp/cuckoding-r040i-proof-5llneac_/connect-browser.py`:
  restarted and authenticated the isolated fixture. Final build used
  `rtk proxy python3 /private/tmp/cuckoding-r040i-proof-5llneac_/start-browser.py`.
  Its first immediate connection lookup ran before BEAM existed; a later lookup
  found the owned child/listener. No product change was needed.
- `rtk proxy python3 /private/tmp/cuckoding-r040i-proof-5llneac_/verify-restart.py`:
  all retained rows and both file hashes survived restart and the final rebuild;
  only startup events appended. Browser showed current and historical acceptance.
- CUA downloaded both artifacts; an exact-byte/hash comparison using
  `rtk proxy python3` passed for both. Original SHA-256
  `50355d28968a79aa438274db5a21c04d62553783de59efe73cec64466ef0dd51`;
  replacement `0f5e84eb01f420c3a086c1a55b55a544750fb6ea5bfaa8f5ac9c8910791b58c9`.
  Source Arena `docs/plan.md` and its unselected canary remained unchanged.
- Screenshots: `/private/tmp/cuckoding-r040i-desktop.jpg` (final bundle) and
  `/private/tmp/cuckoding-r040i-mobile.jpg`. QA tabs closed and viewport reset.

Final tested bundle: `/private/tmp/cuckoding-r040i-target/release/bundle/macos/Cuckoding.app`.
Native SHA-256 `8ad7026b61dbf8c1b8db823b306c9aeb22a168701937a257ea10ac98a5cac04e`;
Specifications BEAM `a9a15a3ee4b201e95927b3d1c77ca8ae7e486ebd41db3134dd890b1d9b16bd3a`;
Storage BEAM `3df750380cdf11c437f4c708fae5ebf94ffc92c318f81ae4ef9a6011400fe083`;
Tabulae BEAM `8ee2e44caffa3c5c231d879e81a50285aa084cdd5f66ee57b60484fadadbdcbe`.
`identity.json` also retains the two changed UI-module hashes. No QA build remains
running; these are tested artifact identities, not claims about another app instance.

No new migration/dependency/native source. Rust unit/lint gates were not rerun for
unchanged native code; bundle compilation and smoke were run. No real-provider
acceptance, autonomous battles, physical sleep/wake, clean-machine installation,
signing/notarization, push or Pages deployment claimed. File sync does not establish
full power-loss durability; same-user path races remain outside this storage boundary.
README, AGENTS and affected docs distinguish accepted intent from execution.

`rtk proxy python3 /private/tmp/cuckoding-r040i-proof-5llneac_/check-docs.py`:
98 local Markdown link targets passed. `rtk git diff --check`: passed.

## Local integration

Implementation commit `40061ef` (`feat(specifications): retain accepted Markdown
task snapshots`) was fast-forwarded into local main with `rtk git switch main`
and `rtk git merge --ff-only feature/r040i-accepted-specs`.
`rtk git branch -d feature/r040i-accepted-specs` removed the merged branch.
`rtk git status --short --branch` confirmed clean local main, 19 commits ahead of
the saved origin/main reference before this task/worklog closeout. No push performed.
The tested package above contains the same implementation. This closeout changes
only task/worklog status; it does not alter the tested application.
