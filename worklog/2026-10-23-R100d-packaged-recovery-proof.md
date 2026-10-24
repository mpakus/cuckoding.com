# R100d — Packaged interrupted-checkpoint proof

Completed on `feature/R100d-packaged-recovery-proof`, base `a81f9ba`; local integration only.
Previous goal turn made progress: R060s combined recovery, actual host/native
format repair and packaged native CLI proof merged. Current plan still requires
broader packaged recovery acceptance. This slice joins real retained Git proof
to SQLite and the actual normal packaged startup/OTP recovery path.

Ponytail full5.3.2 MIT; menubar, OTP, runner, security, architecture and quality
guidance. No provider usage or existing workspace/profile access. Preserve
`Untitled.md.age` unread/unstaged. Exact source/protocol commands use RTK proxy.
The fixture generator is test-only and refuses ordinary/default data roots.
Do not add a production fake-provider or migration bypass.

## Result and review

`1ec2ff0` extends only the existing native smoke lifecycle. An explicit held
mode emits one fixed readiness marker, maintains ordinary five-second
authenticated heartbeats, and releases on input/EOF or a ninety-second ceiling.
Timeout/heartbeat errors pass through normal Service shutdown before failure.
Held mode passes the harness's isolated HOME as metadata-only discovery, like
the ordinary tray; provider HOME/grants remain unchanged. Ordinary smoke is
unchanged. D055 records the boundary before implementation.

The source-only `.exs` builder refuses non-test environments, noncanonical/
linked/unmarked/populated roots and reuses no data. The Python harness creates
its private temporary root/marker, holds the exclusive shell lock while building,
and releases it before packaged boot. Normal domain intents and actual sealed
native Git operations initialize a two-file repository, prepare/capture two
independent edits, integrate the first and combine the second. Synthetic role
replies run only through the existing injected test callback; no provider is
launched and its executable stub cannot perform inference. Normal receipts are
committed inside the owned supervised worker. The final native combination is
deliberately left unsettled in SQLite after its real native effect/cleanup.
Stopping that source VM leaves the exact uncertain checkpoint for normal startup.

The actual sealed app then owns bootstrap/session/heartbeat and normal production
BattleRunner recovery. Complete proof pauses before Secutor (no configured command
checks in this fixture). A second fresh fixture removes its exact own receipt;
startup retains attention without rebuilding it. Assertions bind exact IDs and
read SQLite readonly, keeping claim tokens/requests in memory. Interrupted history,
other attempts, frozen snapshots/criteria, turns/deadlines, reviewed head, source
index/bytes and native proof remain intact. No new provider claim or native replay.
Second boots must not resume either fixture. The harness accepts no data-root
argument. Failed fixtures/logs remain private and are not reused as proof.

Self-review traced input/EOF/timeouts through existing Service ownership and
shutdown, metadata-only discovery, exact fixture scope, test-only provider code,
read-only assertions and private outputs. No new native workflow operation,
migration, dependency, provider grant, UI setup step or production test override.

## Verification

- `rtk proxy env PATH=<pinned> mix quality`: **614 passed**, compile warnings as
  errors, strict Credo **2276 mods/funs, no issues**, Sobelow and both dependency
  audits. `.ccoding/r100d-quality.log`. Existing migration-module and Sobelow
  generated-lockfile warnings remain tool diagnostics; no advisories suppressed.
- `rtk proxy env PATH=<pinned> cargo test --manifest-path desktop/src-tauri/Cargo.toml
  --locked`: **106 passed, 7 ignored**, 228.41s. `.ccoding/r100d-native-full.log`.
  Ignored live/OS tests were not run. Format/check and strict all-target Clippy
  passed (`.ccoding/r100d-clippy.log`).
- The deadline-gate mutation fails the focused release/heartbeat regression;
  restored source passes both held-smoke cases. `.ccoding/r100d-mutation-focused.log`
  and `.ccoding/r100d-held-final.log`. An initial broad mutated run also inverted
  the zero-duration loop and timed out; its known test process was stopped after
  PID/start/executable verification. No app/provider process was signalled. The
  source was restored in `finally` and the final tests rerun.
- `rtk proxy env PATH=<pinned> bin/dev.build`: passed, strict/deep ad-hoc seal and
  retained build receipt. `.ccoding/r100d-build.log`.
- `rtk proxy bin/smoke`: normal authenticated fresh smoke passed; retained data
  `/private/tmp/ccoding-smoke.J9ZydC`, `.ccoding/r100d-smoke.log`.
- The first packaged read passed complete recovery. Its missing-proof assertion
  initially rejected the expected review → needs_attention task transition;
  the regression was corrected to require that state while preserving its lane,
  candidate and evidence. No product behavior changed. The next complete run
  passed input/EOF/actual timeout and both recovery outcomes. The final unchanged
  regression then also passed both second boots without automatic Resume/new
  claims and populated/linked-root refusal. `.ccoding/r100d-packaged-proof-final.log`
  and `.ccoding/r100d-packaged-proof-verified.log`; public assertions with
  build/helper identity in `.ccoding/packaged-recovery-smoke.json`.
- Python syntax compilation, explicit fixture `mix format --check-formatted`,
  application input-digest equality after mutation restoration and Git diff
  whitespace checks passed. Only this turn's generated bytecode cache was removed.
- Final complete fixture `/private/tmp/cuckoding-packaged-recovery-ys28gujk` pauses
  before Secutor. Missing-proof fixture `/private/tmp/cuckoding-packaged-recovery-r3rcsnbg`
  remains attention at combine. Both repeat boots preserve all claims/task state.
  The final timeout fixture is recorded in the private JSON evidence. Its actual
  ninety-second wait ends with normal backend shutdown, Quit event and released
  lock; the expected shell exit is one. All final fixture locks were reacquired
  successfully; no owned shell/backend/test process remains.
- Local documentation target check: **264 targets exist** before the final task
  worklog link; subsequent link/whitespace validation also passes. No site/UI
  rendering changed in this slice.

`<pinned>` PATH:
`/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/opt/homebrew/opt/erlang/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`.

## Artifact and remaining gates

Actual `desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`, build
**`6b9b5053-2050-4aaa-90f7-cd1b247d2adc`**, source `a81f9ba` with a dirty observation,
schema18, Elixir1.20.3/OTP28.5/Rust1.97.1. The digest matches the finished application
inputs; later commits/docs do not make this a clean-source/reproducible claim.
Private immutable build receipt `.ccoding/build-receipts/6b9b5053-2050-4aaa-90f7-cd1b247d2adc.json`:

- Input SHA-256 `62c98fcdea89ad4d162d9a9ef7cbf71b05e25bdd92a18a5df93c07f27b191d50`.
- Helper SHA-256 `ac6ec7a8b45c6859f5c5b760fc330e04c650e150b293ba994287e3c43b473af2`.
- Resource manifest SHA-256 `0a48766ebbfc2f65dfd17f43e49edda1915bc73c17d72f9897eaa81f8e9a7457`.

This proves only the synthetic packaged checkpoint/lifecycle. Real-account
execution/parallel review, full native/process recovery, physical sleep, general
toolchain containment, timed human onboarding and signed/notarized clean-machine
update/restore acceptance remain open in PLAN. Claude subscription sign-in still
requires Anthropic approval; no API-billing fallback. No user workspace/profile
was opened, copied or reset; `Untitled.md.age` stays unread/unstaged. Local main
integration only; no push/publication. Full goal remains active.
