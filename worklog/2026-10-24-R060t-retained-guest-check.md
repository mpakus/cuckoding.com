# R060t — Complete retained guest-check inspection

Implemented and verified, base `ae041a3`, 2026-10-24. Previous goal turn made authoritative progress:
R050r merged with actual guest failure/repair delivery and package evidence.
The full beta goal remains active; no repeated blocking condition applies.

RTK and Ponytail full5.3.2 MIT, local-runner, architecture, security and quality
guidance. No subagent, provider inference, profile copy, reset, push or publication.
The unrelated encrypted file remains unread and unstaged. Claude subscription
sign-in remains disabled pending confirmed Anthropic approval.

Native retained-proof inspection is the required first boundary before an OTP
consumer may recover a completed check stage. Existing complete private proof
already includes wrapper-group closure; a keeper-only closure is insufficient.
Keep the native read separate from workflow authority and never rerun a check.

## Implemented boundary and review

`arena_git::guest_check::recovery` accepts only the fixed four-field recovery
query (plus the exact original optional feedback policy). The caller supplies
the frozen run/attempt/check/input/candidate/command and image binding; manifest
identity comes only from the verified retained capsule. `Store::retained_run`
never creates a missing namespace. Pinned admission/request/intent, native keeper
publication, wrapper receipt and original output are all required. A fixed keeper
read retains its executable mode/owner/link/size checks without weakening ordinary
private file reads.

The reader verifies the current image and owned candidate, reconstructs expected
gzip boot bytes in memory, matches the embedded keeper and exact original typed
VM/helper closure, and recomputes output/excerpt hashes. Repeated reads change no
source/artifact, create no VM/provider/project command and signal no process.
Expired original deadlines can be read as historical data; the native inspection
still has its own cancellable 60-second limit and the caller a 65-second ceiling.
No SQLite recovery consumer, Start policy, checkpoint or public log grant is added.
That consumer remains the next implementation step, not completed recovery.

Self-review traced native dispatch/budgets, Store callers, original request
validation, closed receipt comparison, boot/image integrity, no-create behavior,
failure feedback and source-only proof drivers. Existing execution still uses
future-deadline validation; only read-only inspection accepts historical shape.
No dependency or provider interface was added. The recovery source is in both
compiled image cohorts; no image fallback is allowed.

## Verification

Pinned tools: Elixir 1.20.3/OTP 28.5, Rust 1.97.1 and Swift 6.4 on Darwin27 arm64.
Every command is prefixed with RTK; pinned tool directories are placed on PATH.

- `rtk proxy cargo test --manifest-path desktop/src-tauri/Cargo.toml --release
  --locked arena_git::guest_check::recovery`: **5 passed**
  (`.ccoding/r060t-native-focused.log`). An initial compile exposed only a wrong
  test-module path/missing PathBuf import; corrected before the passing run.
- `rtk proxy cargo test --manifest-path desktop/src-tauri/Cargo.toml --release
  --locked`: **131 passed, 7 opt-in tests ignored**, 241.93seconds
  (`.ccoding/r060t-native.log`). New cases cover pass/fail/feedback, expired data,
  exact scope, altered/absent/linked/public-mode artifacts, keeper-only proof,
  malformed cleanup, cancellation, no-created runs and the 60-second budget.
- `rtk proxy cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check` and
  `rtk proxy cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --release
  --locked --all-targets -- -D warnings`: pass (`.ccoding/r060t-clippy.log`).
- Mutation: replace the exact `retained != row` wrapper comparison with false,
  then run the `keeper_only_or_altered_wrapper_proof` native test. It fails on
  forged cleanup as required. Exact source is restored in `finally`; the full
  native suite above passes afterward. `.ccoding/r060t-mutation.log` retains red.
- `rtk proxy cargo audit --file desktop/src-tauri/Cargo.lock`: exit0, zero errors,
  seven existing transitive warnings (`.ccoding/r060t-audit.log`), not release
  acceptance. No lockfile changed.
- `rtk proxy mix quality`: **648 passed**, format/compile/warnings-as-errors,
  strict Credo and Hex/Sobelow scans pass (`.ccoding/r060t-quality-final.log`).
  Lockfile-reading tooling still emits quoted-keyword warnings.
- `rtk proxy python3 -B test/build_info_test.py`: **4 passed**. Native proof
  drivers parse; documentation references and diff whitespace are checked.

The first sealed build `3028f230-9d6e-40bd-8dca-eb28582b946d` passed packaged
smoke, but the real-guest driver refused at admission before VM/provider effects:
the BEAM source list omitted the newly pinned recovery module. The failed fixture
`/private/tmp/cuckoding-r060t-awb638u8` and complete image receipt remain intact.
Added a cross-language ordered-source-byte cohort regression: it failed on the
exact two differing hashes (`.ccoding/r060t-cohort-red.log`). Updating the BEAM
list fixes the cause; the final648 suite passes. A new sealed build and fresh
actual-VM proof verify the corrected cohort rather than reusing that failed run.

Only the inactive repository Cargo debug build cache was removed to free disk
space, after checking no cargo/rustc/clippy process was running. Private runtime
artifacts, previous bundles/proof, user data and profiles were preserved.

## Final sealed artifact and real proof

`rtk proxy bin/dev.build` passed after the cohort fix
(`.ccoding/r060t-build-final-retry.log`). The first rebuild attempt stopped during
generated release removal because Finder recreated `.DS_Store`. Metadata showed
that lone generated file and no executable running from either generated output;
the normal builder then completed. No user application was killed or data reset.

- Build **f67fb0fc-1f2a-4001-909d-2a3bb43a51d6**, schema21, dirty base
  `ae041a394e2a7a601cb81ca11c5305c4906f0361`, strict/deep ad-hoc seal.
- Application input SHA256
  `f7994ee298ba6e1d41691162b5875412e84d6baaf7f1c57bebd97c665fb576a8`.
- Helper SHA256
  `ac63a978f0642dc4b60a0072d229c8c5395660b51edfbb33db0a1e05f15f352f`.
- Immutable artifact receipt
  `.ccoding/build-receipts/f67fb0fc-1f2a-4001-909d-2a3bb43a51d6.json`.

`rtk proxy python3 -B test/guest_battle_smoke.py --check-recovery` passed
(`.ccoding/r060t-vm-proof-final.log`) in fresh private synthetic root
`/private/tmp/cuckoding-r060t-4vdh5mul`. Its `verified.json` binds the final
build/helper. Two generated dependent tasks finished through six actual offline
npm/Mix VMs, failed-test repair, independent final review, responsive OTP
coordination, original source/index preservation and image reuse/Pause/Stop.
The retained sealed schema20 bundle refused the schema21 database without changing
its hash/integrity. All provider replies were source-only synthetic adapters;
no inference or saved profile was used.

The new native inspection phase constructed queries from original immutable
attempt snapshots, read every one of the six exact pass/fail receipts twice,
refused seven foreign/partial cases (including keeper-only closure), then read
the original proof again after restoration. All original artifact hashes and
run keys stayed intact. Private frames remain inside the fixture. A separate
representative pass/fail repeat additionally checks source file identities,
contents and the original Git index through the same helper; this assertion is
retained in the proof driver. No check is replayed and no workflow recovery is
enabled by this native prerequisite.

`rtk proxy bin/smoke` passed on this final build (`.ccoding/r060t-smoke-final.log`):
authenticated bootstrap/cookie, replay/origin refusal, heartbeat, graceful quit
and listener cleanup. Data is retained at `/private/tmp/ccoding-smoke.fikKVw`.
No LiveView layout/event behavior changed, so no new screenshot/browser run was
needed. Packaged combined-recovery, real-provider and physical-sleep acceptance
are not claimed from these native checks.

## Local integration and next work

The user's follow-up requests all local work merged and merged branches removed.
Inventory found only `main` and this task branch, with one worktree. Changes are
split into core native/cohort, proof-driver and documentation commits, then
fast-forwarded to local main and the task branch removed. No push/publication.
The unrelated `Untitled.md.age` remains unread, untouched and unstaged.
Core native/cohort implementation: `ead245f`. Final structural checks verify
310 local references, Python syntax, formatting/whitespace and exact current
application/helper hashes against the sealed proof. All proof launchers are
confirmed terminal; no user application was opened.

Updated AGENTS/README/PLAN and architecture/security/execution/testing decisions
with the exact boundary. Corrected README's stale schema18/date to current
schema21/2026-10-24. The goal remains active: the next recovery slice must wire
this verified reader into the exclusive supervised queue, retain Interrupted
attempts/dated observations, require every ordered check and pause for explicit
Resume. Dependencies/platforms, hard keeper loss, remaining providers and
real-account parallel/custom-stage/ten-minute acceptance, broader native/physical
recovery and signed release remain open. Anthropic approval is still unconfirmed.
