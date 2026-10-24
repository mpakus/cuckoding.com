# R050q — Planned task checks

Implemented and verified, base `9abfde1`. Previous goal turn made verified progress: R050p
merged offline guest checks with actual VM/OTP, schema fence and package evidence.
The beta goal remains active. No no-progress/blocker threshold applies.

Ponytail full5.3.2 MIT; architecture, OTP/LiveView, workflow, adapter, local-runner,
security and quality guidance. RTK throughout; no subagents, provider inference,
real workspace changes, push or publication. `Untitled.md.age` stays unread and
unstaged. Claude subscription sign-in still awaits Anthropic approval.

Chosen next path: planning proposes closed fixed verification profiles on task
cards. One Start, not model prose, freezes the permitted scope. Per-task scope and
retained-subset final checks are necessary for multi-directory/dependent tasks;
running every future task's commands on every earlier task would break this flow.
Keep separate explicit Arena checks mandatory for every task and final result.

## Implementation

`brief-plan-v4` proposes at most four closed npm-test/Mix-test profiles per task.
The host validates profile/folder/timeout, duplicate pairs and proposal-wide
8-command/600-second limits before automatic import. Stable content IDs and
collision-free bounded display labels retain exact configured declarations when
a proposed literal command matches. A regression caught repeated npm profiles
in different folders being rejected by duplicate display names; that is fixed.

Profiles live in immutable task revision JSON, projected through a nullable
virtual field. Omitted legacy edits preserve the field; absent historical fields
keep accepted-spec serialization/hashes unchanged. The existing task dialog
inspects/edits profiles; planning/history/evidence show the same projection.
Dirty text, revision/session/form scope, active-work locks and native keyboard
focus/disclosure behavior remain. Browser checks caught missing number-input
styling; the shared form selectors now cover it at desktop/mobile sizes.

Start freezes `planned-checks-v1` membership and concrete commands under the
existing guest policy. Tasks check own/integrated work and explicit configured
checks; final checks cover retained tasks and configured checks. Integration
records membership with reviewed head. Skip cannot remove configured checks.
Empty subsets require independent inspection, never invented command receipts.
Original check-attempt/candidate binding, combined/wave review, exact providers,
capacity, cleanup and budgets remain. Prompts disclose Linux/offline/unprovisioned
project dependencies. Schema twenty is additive/forward-only; the normal private
DB backup precedes migration and older bundles refuse it.

## Verification

Pinned Elixir1.20.3/OTP28.5, Rust1.97.1, Swift6.4, Darwin27 Apple Silicon.

- `rtk mix quality`: **640 passed**, format/compile with warnings-as-errors,
  strict Credo clean, Hex/Sobelow no vulnerabilities. Final retained log:
  `.ccoding/r050q-quality-final-verified.log`. Migration fixture redefinition and
  upstream lockfile quoted-keyword warnings remain separate from compile results.
- `rtk proxy python3 -B test/build_info_test.py`: **4 passed**.
- Native locked release tests: **125 passed, 7 opt-in ignored**; the release
  profile avoids rebuilding the removed debug cache, not assertions. Includes
  current Codex v4 schema and Cursor v3/v4 no-tools/hostile callback fixtures.
  `.ccoding/r050q-native-final.log`.
- Native format and locked release/all-target clippy with `-D warnings`: clean.
  Unsuppressed `cargo audit`: exit0, zero vulnerability errors, **7 transitive
  warnings**, including existing platform/dependency maintenance/unsoundness
  notices. They are not a release waiver. `.ccoding/r050q-clippy.log`,
  `.ccoding/r050q-audit.log`. No dependency changed.
- Removing integrated-task check membership makes the exact scope regression
  fail (`.ccoding/r050q-mutation.log`); original bytes were restored. The first
  ephemeral harness expected a different test-summary string, so its final
  assertion failed after correctly detecting the mutation; the retained failed
  assertion is the scope defect, not a compile/tool error. Later full quality
  verifies the restored implementation. Separate repeated-folder red/green:
  `.ccoding/r050q-directory-red.log` then final full quality.
- Real browser, source UI and recognized disposable synthetic workspace only:
  generated profile visible; keyboard Tab/Enter disclosure; dirty criteria/time
  survive add/remove; Save commits revision2 and reopening retains exact values.
  Shared form styling verified after rebuilding CSS (hot-watch retained its old
  input until a rebuild/reload). Desktop1280x720 and390x844 scroll/focus controls
  pass; no warning/error console entries. Screenshots retained privately at
  `.ccoding/r050q-task-dialog.jpg` and `r050q-task-dialog-mobile.jpg`.
  Normal launcher handshake; no cookies/tokens printed. Graceful authenticated
  controller shutdown completed; fixture retained and temporary tab closed.
- Earlier sealed R050q builds `beccd7a4-2148-46f4-a4cf-d0a88ca2cf84` and
  `7a1dd497-27b2-478c-8c6b-dbb693dfef38` each passed six actual VM checks through
  the source OTP loop with synthetic providers, exact output/closure, failure/
  correction/final review, image reuse/Pause/Stop and schema19 old-bundle refusal.
  These precede the final repeated-folder/display fixes; final artifact below is
  verified separately. Private roots `cuckoding-r050q-m43rinln` (also browser
  fixture) and `cuckoding-r050q-kmnnyv9o`, under `/private/tmp`.

Intermediate sealed local-preview build: `312a2dc9-ec97-42d1-bbb8-5b0ee83c5da1`, schema20,
source base `9abfde1` plus this dirty implementation, content SHA256
`705c6ecebd478f4c06fddfeed9516b368947cfed45ac71e1bde8445c403a08f2`;
helper SHA256 `22a54508848e9afc7d3a8da3ed8fd6bd1e8bd0003239e08381f385e37a221bf4`.
Strict/deep ad-hoc seal and private build receipt retained. This is not a clean
published/release artifact. It passed the six-VM loop and package lifecycle/recovery before the final public-evidence projection fix. Final artifact evidence follows below.

Disk pressure was resolved by removing idle regenerable Rust debug objects only,
after verifying no compiler was active; helper executables, old sealed bundles,
all receipts/failed fixtures, source and user data were retained. No reset,
provider inference, account login, real project-folder mutation or publication occurred.

## Final artifact and review

Review traced all planning/storage/import/specification, Start/admission/check,
review/integration/Skip, task UI/history/export and migration consumers. The
frozen-evidence reader initially omitted the new field; it now projects at most
four rows of profile/directory/timeout only. Domain, LiveView and authenticated
export regressions first failed, then passed; private/unknown keys remain absent.
Legacy history remains byte-compatible. No provider tools, native operations,
permissions or dependency were added; schema/profile inputs are data until Start.

After that final change, `rtk mix quality` again passed **640 tests**, strict Credo
and audits (`.ccoding/r050q-quality-sealed.log`). All application input bytes
match sealed build **`e35eb584-34f9-40ba-b9db-0a9049495155`**, schema20, content
SHA256 `4ec5c40265b5f6fb811964d5c1767a4be25a228937e81e011763b8efbddd93fc`,
helper SHA256 `64158f3f7f8d74da06342fbc669b1e26dc6bcd3133a2d5a97924359790572ef5`.
Metadata honestly retains dirty base `9abfde1`; local integration changes Git
revision metadata, not those sealed input bytes. No release/signing claim follows.

On that exact final build:

- `rtk proxy python3 -B test/guest_battle_smoke.py --task-checks`: **passed**;
  `/private/tmp/cuckoding-r050q-n3ffoxge/verified.json` retains exact artifact,
  six real VM checks, generated v4 tasks, no configured Arena commands, independent
  reviews, failed-test correction, dependent-task integration and final checks.
  Private output bytes/hashes, native Stopped/group cleanup, source/index integrity
  and responsive coordinator verified. Second Start reuses the verified image,
  pauses before provider/VM work and stops cleanly. Retained sealed schema19 app
  `f5fea84d-0e06-4535-a261-431c97c3f5f9` refuses schema20 with the exact
  newer-schema reason, unchanged DB hash and SQLite integrity. No inference.
- `rtk proxy bin/smoke`: **passed**; strict/deep seal, bootstrap, cookie handoff,
  replay/origin refusal, heartbeat, graceful quit/listener cleanup. Disposable data
  retained at `/private/tmp/ccoding-smoke.WBhwlh`.
- `rtk proxy python3 -B test/packaged_recovery_smoke.py`: **passed**; retained
  combined checkpoint pauses for explicit Resume, missing proof stays attention,
  second restart never resumes, budgets/history/source/proof unchanged. Owned
  input, EOF and 90-second timeout shutdown pass. Exact final build recorded in
  `.ccoding/packaged-recovery-smoke.json`; log `r050q-sealed-recovery.log`.
- Local Markdown references and `git diff --check` pass. Work is split into the
  design contract, native schema, immutable planning/storage, Arena/UI/evidence,
  source-only proof harness and documentation commits, then fast-forwarded to
  local main. No push or publication; unrelated encrypted file remains untouched.

Remaining beta gates: useful bounded failure-output delivery to repair roles;
project dependencies/platform/distribution/licensing; uncertain keeper/native/
physical-sleep recovery; remaining providers, real-account task/parallel/custom-
stage acceptance and clean-machine signing/update/rollback/release. Claude uses
subscription sign-in only after Anthropic approval, which is not established.
The beta goal remains active; this is completed R050q implementation/local proof,
not complete beta acceptance. Existing real data/profile roots were not opened,
reset, copied or repaired, including the unrecognized saved-data root.
