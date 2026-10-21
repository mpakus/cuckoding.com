# R080h — Task evidence

Claimed after R100a merged as 41d3b47. Ponytail full 5.3.2 (MIT), local
workflow/LiveView/observability/quality/security and Addy incremental/review
guidance apply. RTK proxy preserves exact formatter/test output and the pinned
Elixir toolchain. Untitled.md.age is excluded.

The existing task dialog exposes current drafts/sources/history, while battle
Inspect lists all attempts separately. Add a bounded read-only task projection
and guarded component inside the existing dialog. SQLite remains authoritative;
no workflow/native/provider grant, command, event, migration or dependency changes.
Opening history must never run an agent or establish completion authority.

## Implementation and review

`Battles.Evidence` joins the exact saved Arena/Tabula/draft/battle, projects only
frozen public fields and pages 20 attempts with a timestamp/UUID cursor plus one
lookahead. Reuses the existing board/time and battle/task/time indexes; no schema
change. An explicit foreign/malformed execution ID never falls back to latest.
Review found a nil Earlier ID could reach an invalid Ecto comparison; a failing
regression now guards that case before querying.

`TaskEvidenceComponent` installs its own session guard, receives the server-owned
board/task/session, and stays in the existing native task dialog. Execution history
starts collapsed, the newest attempt starts expanded, and existing disclosure
states survive patches. Earlier/Latest execution is explicit; incoming work cannot
replace the selected run. Older pages retain their rows while reading, and cursor
navigation remains stable after newer attempts arrive. Dirty draft text stays
separate from frozen criteria. Attempt-page actions focus/announce the page label;
opening history causes no workflow command, native I/O or provider usage.
Final wording says retained failed/interrupted/expired receipts are not accepted
completion receipts, and points to separate recovery observations in battle
Inspect. This preserves R060g's independently reconciled integration boundary.

Review covered foreign IDs, immutable authority, nested field allowlists, SQL
binding/limits, escaped HEEx text, session expiry, stable input/history and exact
public binding labels. Requests, claim tokens, raw provider fields/thoughts and
full event payloads never enter the projection. Retained expired/interrupted/
failed attempts explicitly do not imply accepted work; final battle review remains
separate. No dependency or native grant changed.

## Verification

- Red: the three domain tests failed before the projection existed. The initial
  UI fixture tried to update a frozen snapshot and correctly hit the immutable
  authority trigger; the fixture now supplies its snapshot at insertion, leaving
  production immutability intact.
- `rtk proxy env PATH=<pinned toolchains> mix test test/cuckoding/task_evidence_test.exs test/cuckoding_web/task_evidence_live_test.exs`: six pass on the final source.
- Same scoped run plus existing board/battle LiveView regressions: 40 pass before
  the additional UI checks. Tests cover changed frozen revisions, exact selection,
  no-write reads, nested private sentinels, foreign IDs, pagination/new arrivals,
  expired evidence, dirty text, explicit history navigation, reconnect and expiry.
- Scope mutation: invert `b.arena_id == ^arena`; domain tests fail (exit 2).
  Original bytes restored and the six focused checks pass.
- `rtk proxy env PATH=<pinned toolchains> mix quality`: 414 tests pass, Credo
  and Sobelow/dependency audit clean. After the final nil-ID guard, the six focused
  tests and strict Credo pass again. Sobelow's existing quoted-keyword lockfile
  warnings remain tool diagnostics; compiler warnings-as-errors pass.
- `rtk proxy node --test test/dialog_test.mjs test/activity_follow_test.mjs`:
  two pass; no new client hook is introduced.
- `rtk proxy env PATH=<pinned toolchains> bin/dev.build`: final build passes,
  including whole-bundle strict/deep ad-hoc verification. `rtk proxy bin/smoke`:
  pass, fresh root retained. Native runtime code is unchanged from R100a's 79-pass,
  five-ignored Rust suite; no new native-suite run is claimed here.
- Markdown file references and `rtk git diff --check`: pass.

Artifact: `desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`, from
41d3b47 plus this slice. Final sealed helper SHA-256:
`3164e42148605ad7a46979451ebc7e8f0b6037fccee195a912de2ba565958aa8`.

## Rendered packaged fixture

Created only a new recognized private fixture under
`.ccoding/r080h-validation/fixture-6b4bec43-880f-48ca-b3ba-d54f2ab95c6e` with
synthetic terminal receipts; no profiles/accounts/project files were imported or
accessed. Fixture seeding logged one transient Exqlite initial pool-lock retry;
the seed completed and later integrity/FKs pass. This is a layout fixture, not
real Arena/provider completion evidence.

CUA inspected the actual Chrome UI of the packaged app at ports 61137/61435,
then the final artifact at 63113. The first render exposed an overlong expanded
receipt list; collapsing individual attempts fixed it. DevTools widths were
explicitly observed as 320, 768, 1024 and 1440; screenshots show wrapping/layout
at those widths (DevTools constrained height, with 320 also inspected at 900
emulated height). Reset device mode and close DevTools afterward. Native numeric
stepper AX editing appended/clamped values; direct triple-click replacement
established the actual widths, rather than claiming the initial attempts worked.

Interactive artifact (helper `98018d6608bf3fc362a4edc5e16464f0818c4ceff155bd1fa7274d9edda03cf3`):
Tab/Return opens Execution history. Mouse pagination shows page 2
and focuses its announced label. Shift-Tab/Return returns to page 1 and focuses
that label. Escape closes the dialog; Return reopens it, verifying focus returned
to its card. Long candidate hashes, file-tool disclosures and expired warnings
remain readable. Console showed only the existing extension logs and one
improvement notice; no app error was observed. Full axe/screen-reader/contrast
instrumentation and timed unfamiliar-user acceptance were not run. The final
warning-copy clarification was rebuilt afterward; focused tests and packaged
smoke pass again, without claiming another interactive session for that text edit.

Native tray control timed out. Each fixture restart used the documented idle-only
fallback: verify exact executable/parent/start/cwd and idle durable states, check
SQLite integrity/FKs, retain a private online backup, then send normal SIGTERM
bound to the backend's kernel audit token. Backend/shell/listener exit is verified
before rebuild; no unrelated process or user workspace is stopped. This fallback
does not emit the tray Quit event. The original unrecognized saved workspace and
its profiles remain untouched; its separate recognition question is still pending.
Final preview backend 29774/native 29773 exited normally through this fallback;
port 63113 is closed. All 23 synthetic attempts remain, integrity/FKs pass, and
the three app-opened disposable browser tabs were closed. No preview remains
running and none of the private fixture data was reset or removed.

Remaining beta gates stay in PLAN: complete uncertain-effect/sleep recovery,
same-board parallel integration, toolchain grants, custom workflow/runtime
coverage, real-account acceptance and signed/notarized clean-machine/update proof.
This task closes task evidence implementation, not those larger gates.
