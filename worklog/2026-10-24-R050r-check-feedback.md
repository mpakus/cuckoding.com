# R050r — Bounded failed-check output

Implemented and verified, base `054f9b3`, 2026-10-24. Previous goal turn made authoritative progress:
R050q merged with generated profile cards, six actual VM checks and package
lifecycle/recovery evidence. Goal remains active; no blocker threshold applies.

RTK and Ponytail full5.3.2 MIT; existing architecture, OTP/LiveView, adapter,
local-runner, security and quality skills. No agents spawned, inference, real
saved profiles, push/publication or reset. `Untitled.md.age` remains unread.
Claude subscription sign-in still requires unconfirmed Anthropic approval.

Choose the existing VM operation's opt-in output projection rather than a new
native arbitrary-log reader. Verified output is already in memory before native
receipt publication. Keep exact original cleanup/digest/candidate bindings and
explicit new-Start data sharing; no new runtime tools or command permission.

## Result and review

New guest-check Starts freeze `bounded-guest-feedback-v1`. The existing native
operation projects at most 4,096 transformed UTF-8 bytes from an ordinary failed
check only after exact output size/hash, unchanged source, VM Stopped and native
group closure verify. Original output and excerpt hashes/counts stay separate;
ANSI/control/bidi removal is not a general secret detector. Historical requests
retain their original shape and 8 KiB response limit; only the new policy permits
16 KiB response frames.

`CheckFeedback` validates the closed excerpt and exact original attempt/check/
candidate/output binding inside `Receipts.bound?`. Private task context retains
the evidence through fresh-worktree correction; newly settled checks replace or
clear it. Assigned review and repair roles receive explicitly historical,
untrusted data. No command, permission, cleanup, retry or completion authority is
derived from text. The 32 KiB prompt ceiling stays fixed: preview reserves worst
case feedback, host check metadata is projected, and only a redundant prior
public summary is omitted when feedback exists. Full criteria, review and
implementation/Speculator text remain intact.

The existing Start disclosure explains sharing. Existing task history/downloads
expose byte/hash metadata only, never the excerpt or its private request ID.
Retention metadata does not prove provider consumption. Migration twenty-one
adds a bounded check-result update trigger with backup and old-bundle refusal;
historical attempts remain unchanged.

Self-review covered callers, rejected receipts, native closure and legacy frames,
prompt bounds, migration fencing, public exports and OTP state ownership. No
unresolved defect was found in this slice. The binding mutation below proved the
regression is effective. No dependency, generic log reader, native operation,
provider inference or new setup step was added.

## Verification

Commands use RTK and the pinned PATH: Elixir 1.20.3/OTP 28.5, Rust 1.97.1,
Swift 6.4 on Darwin 27 Apple Silicon. Logs below are local ignored artifacts.

- `rtk proxy mix quality`: **647 passed**, format, warnings-as-errors compilation,
  strict Credo and Hex/Sobelow scans pass. Log `.ccoding/r050r-quality-final.log`.
  Dependency tooling emits quoted-keyword warnings while reading the lockfile;
  no vulnerability was reported. An earlier run expected `invalid_result` for a
  forged binding; the correct domain result is `foreign_result`. The assertion
  was corrected before the final run.
- `rtk proxy cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check` and
  `rtk proxy cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --release
  --locked --all-targets -- -D warnings`: pass (`.ccoding/r050r-clippy.log`).
- `rtk proxy cargo test --manifest-path desktop/src-tauri/Cargo.toml --release
  --locked`: **126 passed, 7 opt-in tests ignored** (`.ccoding/r050r-native.log`).
  The separate real VM proof below is not included in that unit count.
- `rtk proxy cargo audit --file desktop/src-tauri/Cargo.lock`: exit zero, zero
  errors and **seven existing transitive warnings**, not release acceptance
  (`.ccoding/r050r-audit.log`). Six unmaintained proc-macro-error/unic entries
  and glib's VariantStrIter unsoundness remain tracked in PLAN.
- `rtk proxy python3 -B test/build_info_test.py`: **4 passed**
  (`.ccoding/r050r-build-info.log`).
  The package-style unittest invocation is unsupported (`test` is not a Python
  package); direct execution is the verified command.
- Mutation: temporarily removed `CheckFeedback.valid_result?` from the bound
  envelope; `rtk proxy mix test test/cuckoding/battle_executor_test.exs:462`
  failed because the forged original-attempt binding was accepted. The driver
  restored exact source bytes in `finally`; full quality then passed 647.
  `.ccoding/r050r-mutation.log` retains the expected red result.
- After the VM proof, strengthened source-only fixture assertions for role-stage
  coverage and cleared task feedback. Extracted a small assertion helper after
  Credo found complexity10/max9. `rtk proxy mix credo --strict` then passed;
  `.ccoding/r050r-credo-verified.log`. Elixir/Python syntax and formatting pass.
  These harness-only edits do not change the sealed application digest. The VM
  run was not repeated for the helper extraction; existing evidence and a
  separate read-only SQLite check already verified both added postconditions.

Focused regressions exercise bounded/UTF-8/control/hash/schema validation,
opt-in response limits, malformed and foreign receipts, failed output reaching
review/repair, fresh successful checks clearing it, export/UI privacy and
schema20-to21 backup/trigger integrity. Early missing-module/helper red checks
are retained separately; final results above supersede them.

## Sealed artifact and actual runtime

`rtk proxy bin/dev.build` passed (`.ccoding/r050r-build.log`). Strict/deep ad-hoc
seal receipt: `.ccoding/build-receipts/d893ce4d-3344-4edc-9e23-d59372e8ec83.json`.

- Build **d893ce4d-3344-4edc-9e23-d59372e8ec83**, schema21, dirty base
  `054f9b3d5617036d5461d19badd006aad2dbc78e`.
- Source input SHA256
  `973540065cf0ef688d6e641e1bc092052ea4b7bdfb0897419c97ff9acd2c1e4a`.
- Helper SHA256
  `89f0b19d924702781e9bdc30bd9486f3211a621c583a9ff4318327b6c3874068`.

`rtk proxy python3 -B test/guest_battle_smoke.py --check-feedback` passed using
only fresh private synthetic root `/private/tmp/cuckoding-r050r-8cnx53j4`.
Its `verified.json` binds the build above. Two generated dependent tasks finished
with **six actual offline npm/Mix VMs**, failed-test correction, independent
final review and unchanged source/index. The source-only provider asserted the
actual serialized prompt delivered the original 925-byte failure to Secutor,
Speculator and Implementor with exact attempt/candidate/output hashes. The driver
compared native private output/excerpt receipts with the immutable SQLite result,
verified no excerpt field in events, responsive OTP coordination, image reuse,
Pause and Stop. Both final task contexts have cleared feedback; the failed
attempt remains immutable. No account or inference was used.

The retained strict/deep-sealed schema20 bundle
`/private/tmp/cuckoding-r050r-old-bundle-0hedj_le/Cuckoding.app` refused the new
database with the exact newer-schema reason; hash and integrity stayed unchanged.

`rtk proxy bin/smoke` passed (`.ccoding/r050r-smoke.log`): packaged launch,
authenticated bootstrap/cookie, replay/origin refusals, heartbeat, graceful quit
and listener closure. `rtk proxy python3 -B test/packaged_recovery_smoke.py` passed
on the same build (`.ccoding/r050r-recovery.log`,
`.ccoding/packaged-recovery-smoke.json`): complete retained combined evidence
restarts Paused at Secutor; missing proof stays needs-attention at Combine.
History/budgets/source/proof remain intact, second restart never resumes, and
input/EOF/timeout shutdown pass. All launchers exited normally.

Browser verification used only that synthetic fixture through the authenticated
source-dev bridge. Task history displayed the 925-byte retained metadata while
the actual failed-test phrase was absent from visible task evidence. Browser
warning/error console was empty. Screenshot
`.ccoding/r050r-task-feedback.jpg` records the existing black/green dialog.
The temporary tab was closed; exact controller PID/start/comm/cwd and shell-lock
owner were checked before graceful SIGINT. Its launcher exited0. No user app or
saved connection was replaced. An initially expired one-use test handoff was
fixed by minting a fresh handoff in the test-only bridge; production auth is
unchanged.

## Integration and remaining gates

Updated AGENTS, README, PLAN, architecture, data, security, execution, flow and
testing docs together. Local references, diff whitespace and build content
identity passed before local-main integration (311 local references, Python/
Elixir fixture syntax and formatted source). Commits remain local; no
publication. The unrelated encrypted untracked file stays unread and unstaged.
Core implementation: `150e0a7`; UI and real-guest proof harness: `399aaca`.
The documentation commit follows on the same branch; integration is fast-forward
to local `main`, then removal of that merged task branch.

The overall goal remains active. Project dependencies/platform and distribution
licensing, hard VM-owner-loss/native/physical recovery, real-provider mixed/parallel
acceptance, ten-minute unfamiliar-user timing and signed release verification
remain open. Claude subscription sign-in remains disabled pending confirmed
Anthropic approval. The saved user data with an unrecognized marker is untouched;
this slice used no profile copy, reset or marker repair.
