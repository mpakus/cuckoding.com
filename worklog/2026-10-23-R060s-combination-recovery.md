# R060s — Retained combined-candidate recovery

Completed on `feature/R060s-combination-recovery`, base `8396de5`; local integration only.
Previous goal turn made progress: R100c backup implementation/verification merged.
Current `docs/PLAN.md` leaves broader interrupted Git recovery open. Existing
combine publishes complete immutable native proof but startup cannot inspect it.

Ponytail full 5.3.2 MIT; OTP/LiveView, workflow, architecture, local-runner,
security, quality and Rust recovery guidance. Reuse repository-owned combination
verification and the exclusive supervised candidate recovery queue. No dependency,
schema, agent runtime permission, provider usage or external publication planned.
Keep `Untitled.md.age` unread/unstaged and saved user workspaces untouched.

Reference source: native `arena_git/worktree/battle/combined.rs` verification,
`candidate_recovery.rs`, host `Battles.CandidateRecovery`, `MixedClosure`,
`BattleExecutor` and existing stage/check/review transitions. No upstream code
copied. Exact-output/source/protocol commands use `rtk proxy`.

## Result and review

New Starts freeze `combination_recovery: retained-combination-v1`. Only one exact
interrupted combination with otherwise settled history may use the existing
exclusive Task.Supervisor recovery queue. `CandidateRecovery` validates the full
bound result; `MixedClosure` explicitly excludes combination members. The native
fixed read verifies the exact original intent, receipt UUID, complete publication,
current reviewed ref/head/config, original captured writer and combined tree.
It rereads retained proof and never recreates or recombines. Native60s/host65s,
cancellation and every original future deadline remain authoritative.

The original Interrupted attempt is immutable. A separate dated observation can
pause at fresh configured checks/independent review for explicit Resume. Old
check/provider authority is cleared, the reviewed head and lifetime limits stay,
and Resume revalidates exact bindings. Missing/invalid proof never establishes
cleanup; late/fenced verified proof permits Stop only. Existing guarded LiveView
Inspect/reconnect/Resume controls are reused; no new setup or ordinary task prompt.

Self-review checked native/host request identity, closed public fields, current
source/ref/config/tree checks, untouched source/index/proofs, missing-proof refusal,
historical policy isolation, mixed-queue scope, transactional audit rollback,
supervised restart and original counters/deadlines. It added an explicit native
UUID guard and a substitution test using another complete valid combination.
The host already refuses that mismatch; the native boundary now refuses it too.

## Actual packaged protocol finding and fix

The initial unit suites passed with status-bearing native preparations. A sealed
CLI proof using Phoenix's actual five-field preparation failed `combine_candidate`
with `candidate_mismatch` on artifact `cd99263a-2f0d-4170-9fce-3eaac555dd0d`.
Native `battle.json` keeps a sixth `status: prepared` field; its comparison used
the caller's five fields unchanged. This was an actual normal-combination bug.

Commit `7b057fc` adds that status only to the in-memory comparison. It does not
rewrite an original request, intent, receipt or worktree. Explicit wrong statuses
and extra fields still fail equality. Combination fixtures now use the actual
host shape throughout normal creation, fresh verification/consumers and recovery.
`408d114` owns native recovery; `0774f15` owns host/OTP/UI recovery.

The permanent `test/combined_candidate_smoke.py` reproduces the exact sealed CLI
boundary on fresh synthetic directories only. The earlier failed fixture remains
at `/private/tmp/cuckoding-r060s-cli-ear1v7l7`; no mutation was retried there.
The final helper completed **14 actual packaged operations** at
`/private/tmp/cuckoding-r060s-cli-3xs5cdqb`: create battle, two separate preparations
and captures, integrate the first result, combine the second, recover it twice
without changing proof/index/working edits, verify the unchanged reviewed head,
refuse a deliberately missing receipt without recreating it, and refuse replay.
No provider profile, login or inference was involved. Replies/result stay private.

## Verification

- New native cases initially failed at missing operation/budget; the host case
  failed at the absent frozen policy. Fixture setup/import errors were corrected
  before treating those failures as red regression evidence.
- `rtk proxy env PATH=<pinned> mix quality`: **614 passed**; compile with warnings
  as errors, strict Credo **2264 mods/funs, no issues**, Sobelow and both dependency
  audits passed. `.ccoding/r060s-quality-final.log`. No warning/advisory suppression.
- `rtk proxy env PATH=<pinned> mix test test/cuckoding/combination_recovery_test.exs
  test/cuckoding/candidate_recovery_test.exs
  test/cuckoding_web/candidate_recovery_live_test.exs`: **28 passed** after the
  policy-gate mutation was restored. `.ccoding/r060s-host-focused-final.log`.
  The removed-policy mutation failed the historical-snapshot regression as
  expected; restoration used `finally`. `.ccoding/r060s-policy-mutation.log`.
- `rtk proxy env PATH=<pinned> cargo test --manifest-path desktop/src-tauri/Cargo.toml
  --locked`: final **104 passed, 7 ignored**, including actual five-field callers,
  UUID substitution, partial/link/tamper/stale proof, no replay, budgets and owned
  cancellation. `.ccoding/r060s-native-full-final.log`. Individual tests perform
  many bounded operations; the suite took228.45s. Ignored live/OS tests were not run.
- `rtk proxy env PATH=<pinned> cargo fmt --manifest-path desktop/src-tauri/Cargo.toml
  --check` and `rtk proxy env PATH=<pinned> cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked
  --all-targets -- -D warnings`: passed. `.ccoding/r060s-clippy-final.log`.
- `rtk proxy env PATH=<pinned> bin/dev.build`: passed strict/deep ad-hoc seal and
  immutable receipt; `.ccoding/r060s-build-final.log`.
- `rtk proxy python3 test/combined_candidate_smoke.py`: passed the actual final
  package, fourteen operations/no inference. `.ccoding/r060s-cli-proof-final.log`
  and `.ccoding/combined-candidate-smoke.json`; helper syntax also checked.
- `rtk proxy env PATH=<pinned> bin/smoke`: final fresh authenticated package smoke
  passed, including protected routes/handoff/origin refusal/heartbeat/graceful
  Quit/listener cleanup; `.ccoding/r060s-smoke-final.log`, data
  `/private/tmp/ccoding-smoke.7cy3zz`.
- The final packaged `Contents/MacOS/ccoding --smoke-test`, with explicit release
  and disposable retained-data root, passed schema18 startup unchanged. Data
  `/private/tmp/cuckoding-r060s-retained-0rzthrmy`; `.ccoding/r060s-retained-smoke.log`.
  SQLite backup came only from the earlier disposable R100c smoke. Prior facts
  match, integrity/FKs pass, only four expected authentication/power/Quit events
  and ephemeral browser tokens change. No redundant backup or profiles were copied.

`<pinned>` PATH:
`/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/opt/homebrew/opt/erlang/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`.

## Actual final artifact and limits

`desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`, build
**`de6713e4-40cb-4f8a-9bad-72230e89f304`**, source `7b057fc` with a dirty observation,
schema18, Elixir1.20.3/OTP28.5/Rust1.97.1. Input digest matches the completed code.
Private immutable `.ccoding/build-receipts/de6713e4-40cb-4f8a-9bad-72230e89f304.json`:

- Input SHA-256: `8c9a2678cb56de21c565295bb03ea46521276ce7b85c21f1583ac91a74441241`.
- Helper SHA-256: `bcca37637fd8de0fab22fc98e984192ae081e2e9b56deb6b13670b14f1855306`.
- Resource manifest SHA-256: `fe4ac42510dfb8e01ba7c11260dc14d11edc5c5580d110ec3b982cc9a010a290`.

Source/data locks were released; no owned smoke process/listener remains. All
failed/partial fixtures stay retained. No actual user app/workspace/profile was
opened, reset or copied. No new migration, dependency, provider grant, login,
inference, push or publication. Product/Flow stale sequential/custom-stage wording
is corrected, without upgrading real-provider acceptance claims.

This proves native/host fixture recovery and the packaged Git protocol, not a
real-provider interrupted battle or full packaged recovery acceptance. Broader
native/process/Git/transport recovery, physical sleep, general toolchains, live
providers/parallel acceptance, ten-minute human setup, signed update/restore and
clean-machine release gates remain open. Claude approval is still unconfirmed.
Packaged CLI regression is retained in `0bc8bd1`. Final `git diff --check`,
270 local Markdown targets, application input digest and actual helper hash pass.
