# R060p — Mixed interrupted closure

Implemented, verified and merged locally. Branch `feature/R060p-mixed-closure`, base `08d843f`.
Ponytail full 5.3.2 (MIT); workflow, local-runner, security and quality guidance.

The provider closure queue currently consumes the provider claim and leaves a
concurrent capture/preparation without an inspection path. Add a versioned
Stop-only observation, reusing exact existing native reads and OTP workers.
No lost provider work or native checkpoint becomes accepted authority.

Unrelated `Untitled.md.age` remains unread and unstaged. No real-provider usage,
saved user workspace changes, push or publication is authorized by this slice.

## Implementation and review

`Battles.MixedClosure` freezes the new Start policy and validates an exact
provider/native pair against immutable requests. Startup retains that pair only
for two restart-interrupted wave tasks with otherwise settled history, without a
prior Stop/timing fence. The existing provider queue runs first; its settlement
queues the native read even when provider proof was unavailable, so independent
closure facts can be retained without promoting uncertain cleanup.

The existing executor/native fixed reads and exclusive supervised worker are
reused. Native observation commits separately, before notification. Neither
original attempt nor task/head/checkpoint/turns/deadline changes. The only new
consumer is all-claim Stop cleanup; quiescence and Resume/Retry/Skip authority do
not use these observations. Existing exact provider-capacity release is unchanged.
Inspect displays only status, date and attempt ID, with no raw envelope/files.
Provider wording now requires every claim to verify before Stop.

Reviewed startup, timing fences, pending-read predicates, immutable receipt
validation, Stop, ordinary settlement and reconnect paths. No additional native
operation, migration, dependency or runtime access is introduced. The separate
validated receipt path is mandatory: missing processes never prove closure.

## Verification

- Focused `mix test test/cuckoding/candidate_recovery_test.exs
  test/cuckoding_web/battle_live_test.exs`: **50 passed** after exact mutation
  restoration. Includes captured/prepared pairs, missing/foreign/false proof,
  both-claim Stop gates, legacy policy, preexisting timing fence, late/fenced
  results, immutable data, coordinator loss/restart and private scoped UI reload.
- `rtk mix quality`: **566 passed**, strict Credo (152 files, no issues), Sobelow,
  format/compile and dependency audits passed, terminal exit zero. Existing
  migration-fixture module-redefinition and audit lockfile quoted-keyword warnings
  remain. Full proof: private `.ccoding/r060p-quality.log`.
- Mutation removed `MixedClosure.closed?` from Stop validation: the focused pair
  test failed with `cleanup_required`. Exact original source bytes restored in
  `finally`; focused suite passed afterward. Private `.ccoding/r060p-mutation.log`.
- `rtk proxy bin/dev.build`: passed and retained strict/deep sealed receipt for
  **2454e5a1-73ae-4632-a2d1-4036559287bf**. Source `08d843f` plus then-uncommitted
  application inputs; digest
  `3881c5ea93d0b07d106c2c8025c9c6157096793318cd25fe989614288d906500`.
  This honest dirty observation is not a release tag or reproducibility claim.
- `rtk proxy bin/smoke`: passed bundled boot/bootstrap/browser cookie/replay/origin,
  heartbeat, graceful quit and listener cleanup. Fresh isolated data retained at
  `/private/tmp/ccoding-smoke.hPk1dU`; no real-user profile copied or launched.
  SQLite integrity/FKs checked after quit, schema seventeen.
- Local Markdown targets (230) and `git diff --check`: passed.

Initial fixtures attempted to update frozen authority; the immutable DB trigger
refused as expected. The legacy fixture now inserts an explicit old snapshot
without changing any existing record. An existing UI wording assertion was
updated to the more accurate all-claims message. No production gate was relaxed.

Native runtime source was unchanged; its full Rust suite and a visual browser
pass were not rerun for this domain/UI-text slice. Real-provider crash acceptance,
general subprocess checks, other interrupted effects, physical sleep and signed
release delivery remain open. No inference, push or publication occurred.

Final review also applied the installed code-review-and-quality skill. Mutation
verification, connected authority paths and public UI projections were checked;
no unresolved actionable issue was found. No review subagent was started.

Implementation `d4a0f98` fast-forwarded to local main; feature branch deleted.
Only unrelated `Untitled.md.age` remained untracked. Local integration is not
remote publication or beta-release acceptance. The new receipt remains a dated
build of the application inputs before the commit, as reported above.
