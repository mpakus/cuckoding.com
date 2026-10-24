# R050o — Native production check keeper

Implemented on `feature/R050o-native-check-keeper`, base `7f8a9e1`.
The previous goal turn made progress: the Tokio patch and sealed lifecycle passed
and merged. This slice implements native VM execution and closure, reusing
R050m/R050n verification rather than trusting the development observer.

Ponytail full 5.3.2 MIT, local-runner, architecture, security, quality, Swift,
Unsafe Rust Checker and code-review guidance. RTK throughout; no subagents,
inference, user profiles, reset, schema migration, push or publication.
`Untitled.md.age` remains unread, untouched and unstaged.

## Implementation and review

D061 records the boundary. Cargo compiles one Apple Silicon/macOS13 Swift6
keeper with warnings denied, signs its sole virtualization entitlement and
embeds the exact bytes. Build identity includes both source and entitlement.
The shell receives no additional entitlement or runtime override.

Fixed `run_guest_check` verifies the original image and native candidate capsule,
source identity and closed literal npm/Mix request. A private single-use run key
and fsynced admission precede preflight. Replays retain original evidence and
report cleanup unverified, including when the prior operation refused before a
VM launch. Owned preflight refusals retain a bound `native_started: false` receipt;
uncertain Git cleanup never becomes verified. Review added the replay regression
and retained the same wall-time baseline through preflight and execution, as well
as the 360-second native admission cap and caller's original absolute deadline.

Descriptor-bound APFS clones avoid duplicating boot images; an exclusive bounded
copy is the fixed fallback. No host archive extraction, caller boot image/helper,
network, storage, socket device, share or provider credential enters the VM.
The root controller and UID1000 worker remain separate. Rust and Swift independently
validate bounded exact scope, output counts/hashes and exit/state invariants.
Validated command output stays in a private hash-bound file; public results contain
no raw output, argv, source path or frames. No new dependency was added.

Swift observes actual SDK Stopped and fsyncs its VM-only closure. Rust must also
finish the owned unreaped helper process group, verify retained files/closure and
publish the final exact receipt. EOF, backward time, expiry and cancellation have
bounded shutdown grace and no invented test exit. Wrapper loss may leave private
VM closure but no overall cleanup receipt. Missing proof stays unverified.
The existing Start grant and Elixir check normalizer still reject this contract.
No recovery, workflow or completion authority was added.

## Verification

Pinned Elixir1.20.3/OTP28.5, Rust1.97.1 and Swift6.4 on Darwin27 arm64. Commands
below ran through RTK from the repository root, with private logs in `.ccoding/`.

- `rtk mix quality`: **615 passed**, compile/format/Credo and Hex/dependency audit
  passed. Existing migration-module redefinition and quoted dependency-key warnings
  remain recorded separately; they were not suppressed.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check` and locked
  all-targets Clippy with `-D warnings`: passed. Latest Clippy log is
  `r050o-clippy-clock.log`, after the retained preflight clock-baseline change.
- Focused `guest_check::`: **4 passed** after that change, covering closed scopes,
  bounds/clock validation, exact closure and single-use preflight/refusal replay.
- Full locked native suite after the final change: **123 passed, seven ignored**,
  zero failed (234.80s), `r050o-native-final-v3.log`. The ignored checks require
  explicitly selected runtimes/fresh profiles or separate provider-usage approval;
  they are not counted as passing.
- `rtk proxy python3 -B test/build_info_test.py`: **4 passed**. An initial unittest
  module-style invocation collided with Python's standard-library `test` package;
  direct script invocation is the verified command, with no product-code workaround.
- `rtk proxy python3 -B test/keeper_protocol_test.py`: passed with Address Sanitizer,
  compiling actual production decoding/private-file code under a compile-time test
  flag, no VM/runtime test override. Fixture
  `/private/tmp/cuckoding-keeper-protocol-yr651lmv`; binary SHA256
  `8da3341b19c3e8df31222c0da3149c3c48da8ae378667f266375d04bab327f15`.
  A source-copy mutation inverted `group_closed`; the same tests rejected it with
  the intended precondition failure (exit -5). Production source was unchanged.
  Mutant fixture: `/private/tmp/cuckoding-keeper-mutation-4wx3ceqj`.
- Fresh unsuppressed `rtk proxy cargo audit --file desktop/src-tauri/Cargo.lock
  --json`: **zero vulnerability errors, seven warnings** (six unmaintained,
  one unsound transitive cohort), unchanged from R103. This is not zero warnings
  or release acceptance.
- `rtk proxy bin/dev.build`: sealed final build below, strict/deep verification
  passed. An earlier rebuild correctly refused while our held packaged test was
  still running. It was retried only after that owned test completed its normal
  shutdown; nothing was killed or the guard bypassed.
- `rtk proxy python3 -B test/guest_check_keeper_test.py`: **all twelve actual VM
  scenarios passed on the final sealed helper**, including image installation,
  npm/Mix pass/fail, output forgery, source mutation, output boundary/overflow,
  timeout, active cancellation, earlier absolute expiry and wrapper loss. The main
  shell has no virtualization entitlement; the embedded keeper has only that
  entitlement. Foreign original image/input receipts refuse before launch; replay
  reports cleanup false and preserves proof. Original source/index bytes survive.
  Validated private output hashes match. Eleven ordinary outcomes prove SDK
  Stopped plus helper cleanup; wrapper loss intentionally has only VM closure and
  no native receipt/overall cleanup. `r050o-keeper-sealed-final.log`.
- `rtk proxy bin/smoke`: passed final build startup/bootstrap, browser cookie,
  origin/replay refusal, heartbeat, graceful Quit and listener cleanup. Private
  fixture `/private/tmp/ccoding-smoke.CSeENQ`.
- `rtk proxy python3 -B test/packaged_recovery_smoke.py`: passed final sealed build.
  Exact complete proof paused at Secutor; missing proof remained needs-attention.
  Repeated restart never resumed or replayed native/provider work, history/budgets/
  source/proof stayed unchanged, and input/EOF/ninety-second-ceiling shutdown passed.
  Synthetic roots: `/private/tmp/cuckoding-packaged-recovery-zsumkff7`,
  `/private/tmp/cuckoding-packaged-recovery-goxb9iky` and
  `/private/tmp/cuckoding-packaged-recovery-357oohnw`. Current evidence at
  `.ccoding/packaged-recovery-smoke.json`, `r050o-recovery-final.log`.
- `rtk proxy python3 -B test/check_input_smoke.py`: passed the prior sealed
  R050o build `62110265-f063-4d0e-9541-a8f2a9394ab1` before the clock-only fix,
  helper SHA256 `c5407fe4347de06c10cef666c7b8ca68164b17a78669f201a278b6fc91bf3a5c`,
  fixture `/private/tmp/cuckoding-r050m-cli-vb1nk593`. Repeated verification retained
  bytes, foreign/tampered/missing receipts refused, source/index unchanged. Final
  keeper matrix independently exercises candidate transport on the final build.
- Changed Markdown local-reference validation and `rtk git diff --check`: passed
  after final documentation edits. No UI/browser visual change in this native slice.

Earlier development evidence is retained rather than substituted for final proof:
`/private/tmp/cuckoding-r050o-2ifgpcu1` passed ten scenarios but its 12-second test
expiry elapsed during preflight, before a VM could start. The fixture was corrected
to allow preflight and use a 45-second original deadline against a 60-second
command limit. `/private/tmp/cuckoding-r050o-b2dmhx45` passed all twelve with the
debug helper. `/private/tmp/cuckoding-r050o-5qt6wbp4` passed all twelve with sealed
build `62110265-f063-4d0e-9541-a8f2a9394ab1`, before the final clock-only change.
The first Swift compile exposed a deprecated Array-to-C-string initializer; the
source now uses the owned realpath pointer. The first protocol fixture used a
macOS `/var` alias; only the fixture changed to canonical `/private/tmp`, preserving
the production canonical-path refusal. No failed run was replayed or overwritten.

Disk pressure was handled only by removing idle owned regenerable compiler caches
and retaining all binaries, image/run/proof files and test logs. No user workspace
or unknown artifact was removed.

## Final local artifact

Build `e4b2acbf-ce11-45b3-bca0-17b035bfdac9`, local-preview, schema18, sealed
2026-10-24T06:37:34Z. Source base `7f8a9e145381136e7d48fdda694efc39650eac90`, dirty
working-tree build; exact source digest binds the final implementation, not a
claim that the later merge commit was compiled.

- Source SHA256: `beb3727e2a695fe5d85c96eb5c65deb2bd5b571ce195298858faa6206c9c0f50`.
- Native helper SHA256: `cfbcf569276efabcc7e24f1205cb0ffe924e4613a7fb67bf8c19854a7eeb8cce`.
- Resource manifest SHA256: `72b80017f27716fbd9a7c5e1fe33cb7eba456783b30844d7e42fb73e11c94dc7`.
- Image specification SHA256: `702418b5314b7740ca0477c844b7dbde70e78a936d9a6993622630ec1d33b816`.

Final VM evidence: `/private/tmp/cuckoding-r050o-_29djd01/evidence.json`,
SHA256 `27e25d2d09ea1b10dc98b839e1a0c8f40869377666dffc7b5b33f8800771229e`.
Image key `8b82c8f5-d6ee-4a3b-ac48-58adffae1103`.
Dedicated keeper SHA256 `23a76220babe97aa32e83af673815378e2069ff79d997d5a196343c8bdbe2220`.
The native build manifest/source digest and strict/deep seal match current inputs;
this remains ad-hoc local-preview evidence, not notarization or release acceptance.

Code was split for review: `a226d90` packages the dedicated keeper and its ASan
checks; `628ee42` adds the fixed native consumer and bound VM matrix. Final docs
and evidence follow in the same task branch. Review covered capability boundaries,
FFI descriptor lifetimes, failure/receipt replay, retained output and deadline
handling; the identified replay and preflight-clock issues were corrected before
integration. No unrelated refactor or runtime dependency was introduced.

## Remaining scope and handoff

Next: freeze explicit image/check authority in new Starts, connect this primitive
through supervised OTP workers and task-owned verification without a setup wall,
and prove settlement/cancellation/interruption against the exact candidate.
Keep historical check contracts unchanged. Real-project dependencies, native
platform equivalence/provisioning/distribution, hard keeper loss/physical sleep,
real-account/mixed parallel acceptance, Claude's unconfirmed Anthropic approval,
Hermes and signed/notarized clean-machine release remain separate open gates.
No new provider inference was authorized or consumed.

Verified for local `main` integration, no push/publication. The overall beta goal
remains active; this primitive is not whole-beta or Arena-toolchain acceptance.
