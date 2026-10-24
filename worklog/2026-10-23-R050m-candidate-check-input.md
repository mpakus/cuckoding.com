# R050m — Native candidate check input

Verified locally on `feature/R050m-candidate-check-input`, base `b7cd25f`.
Previous goal turn made progress: R050l ran actual offline npm/Mix checks with
separate privileged control and native closure. Implement the production
candidate transport that the guest runner will consume.

Ponytail full5.3.2 MIT; architecture, runner, security, OTP, quality and Rust
guidance. RTK throughout. Keep `Untitled.md.age` unread and untouched. No provider
inference, personal profiles, real Arena mutations or publication are authorized.

Implemented the production native `prepare_check_input` / `verify_check_input`
operations and the closed `LocalGit` metadata projection, with fixed 60-second
native/65-second host budgets. They are internal transport operations; no UI
command or battle grant invokes them yet.

The producer binds the exact retained preparation/source/head/tree, validates the
locked owned checkout/index/raw bytes and exports immutable Git blobs. It creates
private intent/newc/manifest/receipt outside the checkout through retained
descriptors, exclusive no-follow opens and fsync. Input files are ordinary guest
UID/GID1000 files under a fixed prefix; Git metadata never enters the archive.
Instruction files remain data. Directory/case aliases, partial/tampered/foreign
inputs and lost cancellation/deadline authority refuse. Verification recomputes
expected bytes into a hash sink, compares every artifact/binding/count and never
repairs missing evidence. Matching a forged receipt to a forged archive cannot
bypass comparison against committed content.

Reused the existing bounded Git blob decoder in `inspection::each_blob` and the
combination path-prefix checks in `portable_paths`. Combination conflict statuses
and raw checkout inspection retain their behavior. No dependency, schema,
provider grant, shell permission, VM entitlement or task-completion authority changed.

Verification used Elixir1.20.3/OTP28.5 and Rust1.97.1 with the pinned PATH:
`/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/opt/homebrew/opt/erlang/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`.
Commands below ran through RTK; private logs are under `.ccoding/r050m-*`.

- `rtk proxy mix quality` — 615 tests passed, formatter/compile/static analysis and both
  dependency audits passed. Sobelow reported no vulnerabilities. Existing quoted
  migration-redefinition drill and lockfile-keyword scan warnings remain; no new
  compiler warning was suppressed.
- `rtk proxy cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked` — 110 passed,
  seven opt-in tests ignored. The subsequent empty-tree regression is test-only;
  the final focused `rtk proxy cargo test ... --locked check_input` passed all five current
  transport cases, without changing production code after the full run.
- Final `rtk proxy mix test test/cuckoding/arena_git_test.exs test/cuckoding/native_helper_test.exs`
  — 20 passed, including the added assertion that a transport receipt cannot pass
  `BattleChecks.normalize`. Native cases cover independent newc decoding plus
  actual system tar listing, binary/executable content and modes, unchanged source/
  index, no uncommitted bytes, repeated verification, replay, forged/tampered/
  missing/linked artifacts, foreign/raw/index-hidden/extra changes, storage
  symlinks, case/file-directory collisions, bounds, empty trees and cancellation.
- `rtk proxy cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check` and final
  `rtk proxy cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`
  passed. The first compile exposed a too-narrow new re-export; visibility is now
  restricted to the owning native Git module and all final builds pass.
- `rtk proxy bin/dev.build` — rebuilt/sealed the full local-preview app and retained build
  receipt `b503a297-eff7-40e6-b3dc-ba3f5ceb6b6d`. Normal vendor relocation warnings
  were followed by re-signing and successful strict/deep signature verification.
- `rtk proxy python3 -B test/check_input_smoke.py` — all nine actual sealed-helper CLI
  operations passed in `/private/tmp/cuckoding-r050m-cli-cyzn16a9`. Exact committed
  binary bytes traveled through the archive while source working changes/index
  remained intact. Repeated verification left proof unchanged; replay/tampering/
  missing receipt refused without rebuilding it. Failed artifacts stay retained.
- `rtk proxy python3 -B test/combined_candidate_smoke.py` — all fourteen existing native
  operations passed, fixture `/private/tmp/cuckoding-r060s-cli-z8y96hst`, including
  exact recovery, source/index preservation and missing-proof refusal.
- `rtk proxy python3 -B test/packaged_recovery_smoke.py` — both actual packaged OTP/release
  cases passed. Complete proof at `/private/tmp/cuckoding-packaged-recovery-bop3nat5`
  reached Paused/Secutor; absent proof at
  `/private/tmp/cuckoding-packaged-recovery-qnpwy8e6` remained Needs attention/
  Combine. Attempts/budgets/head/proof stayed intact, repeat boots did not Resume,
  there was no provider/native replay, and graceful shutdown passed. Its lifecycle/
  refusal/timeout checks also completed with exit0. These use explicitly synthetic
  setup/provider history, never real-account acceptance.
- Smoke Python AST, changed-document relative links and exact built source-input
  digest passed. The unrelated encrypted file remains unread and unstaged.

Sealed artifact: `desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`.

| Observation | Value |
| --- | --- |
| Build | `b503a297-eff7-40e6-b3dc-ba3f5ceb6b6d` |
| Source input SHA-256 | `6ddee469a5fe13e926f9a68ef72e0733350d687d8de1bfe7f42c9cf34dd4e8bd` |
| Native helper SHA-256 | `319b9d6681d4bdca5f73807e7d9d125bf266014185af99d4a651faf51231fbd8` |
| Sealed resources SHA-256 | `4ad2ac557539d2d1f5ca69bcbbc6248b439106e69ee94434713d03d7d97de9ca` |

The build records base `b7cd25f` with a dirty source observation, schema18 and
local-preview/ad-hoc status. The matching current input digest was rechecked;
this is not Developer ID/notarization or distribution acceptance.

Review covered exact source/receipt binding, descriptor lifetime, private file
creation and read-only verification, cancellation/partial effects, closed public
projection, bounded memory/I/O, legacy parser/combination behavior and source
preservation. No remaining issue was found within this transport slice.

Handoff: the production transport exists and is verified. Next integrate a
provenanced frozen guest image, native keeper/closure and check grant with durable
OTP stages and the existing one-Start UI. General Mix/npm execution remains
disabled until that integration and real-project acceptance pass. Real providers/
parallel battles, broader recovery/physical sleep and release verification remain
open. Claude subscription support still requires Anthropic approval; no new
inference or sign-in was attempted. No real saved workspace was launched.
