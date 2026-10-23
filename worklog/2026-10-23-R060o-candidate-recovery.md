# R060o — Retained candidate checkpoint recovery

Claimed on `feature/R060o-candidate-recovery`, base `fcea29a`. Previous goal turn
made verified progress: R050h custom writers, schema barrier and bundle acceptance
merged. `Untitled.md.age` stays unread/untouched/unstaged.

Ponytail full 5.3.2 MIT, RTK, local-runner, security, architecture, OTP/LiveView,
workflow and quality guidance apply. Exact source/protocol/check output uses
`rtk proxy`; no new dependency or provider usage.

Initial toolchain investigation: current checks deliberately set irreversible
RLIMIT_NPROC=0. Allowing fork would need a new process-tree ownership proof, not
just group disappearance. Installed Apple SDK `sys/event.h:357-362` explicitly
marks NOTE_TRACK/NOTE_TRACKERR/NOTE_CHILD unsupported since 10.5. Apple's XNU
`bsd/kern/kern_prot.c` and `bsd/kern/kern_event.c` were inspected as primary
references. No upstream code was copied or executed. General toolchains remain
required; their grant was not weakened or relabelled complete. Continue through
an independent actual recovery requirement while that containment design remains
unproven.

Design acceptance: exact retained native capture proof; no replay; bounded
supervised one/two-member capture/preparation reads; all-or-nothing checkpoint;
explicit Resume; original budgets/slots/deadlines/bindings and public Inspect.

## Implemented

New Starts freeze `candidate_recovery: retained-candidate-wave-v1`. The native
`recover_battle_candidate` reads only the exact original capture request,
intent/publication/receipt, original preparation/battle tag, current source/ref
and unchanged owned checkout/index/bytes. It shares the capture manifest validator
and existing candidate verifier. Missing evidence is never reconstructed. The
operation has a 60-second native / 65-second host ceiling inside the original
stage/battle limits.

`Battles.CandidateRecovery` validates queue membership and normalized observations.
Battles retains Interrupted attempts and dated public reads, and advances every
member together only after all proofs pass. One/two captures and either ordering
of a mixed preparation/capture pair use the existing exclusive supervised worker.
The worker commits its domain result before notification. Restart during the
second read preserves the first observation and repeats only that unfinished
read, never capture or inference. Final checkpoint is Paused for explicit Resume;
expiry/timing fences permit verified Stop closure only. Old policies and pure
preparation queues keep their existing behavior. Inspect adds public dated status
inside its existing guarded component, without requests, file lists or tokens.

No dependency, grant broadening or schema migration was added. Schema seventeen
and its existing compatibility barrier remain authoritative.

## Verification

Commands ran with the pinned Elixir 1.20.3-OTP28 / OTP 28.5 / Rust 1.97.1 PATH:
`/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/opt/homebrew/opt/erlang/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`.

- `rtk proxy env PATH=<above> mix quality`: **552 passed**, format,
  warnings-as-errors compile, strict Credo, Sobelow and dependency audits passed.
  Existing migration-redefinition / dependency quoted-keyword warnings remain;
  no check was suppressed.
- `rtk proxy env PATH=<above> cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`:
  passed.
- `rtk proxy env PATH=<above> cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`:
  passed.
- `rtk proxy env PATH=<above> cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`:
  **97 passed, 5 existing environment-dependent ignored**, 221.12 seconds.
  The final focused retained-capture test (including linked evidence and no
  receipt reconstruction) also passed, 39.73 seconds.
- Ten focused domain tests cover atomic mixed waves in both orders, missing/
  foreign/legacy proof, expiry/timing Stop-only closure, false cleanup, custom
  pre-Implementor continuation, supervised serialization and coordinator restart.
  The focused LiveView test covers pending/dated public observations and token
  exclusion. Old preparation recovery tests remain passing in full quality.
- Mutation check changed the all-members proof condition from `Enum.all?` to
  `Enum.any?`: the missing-proof regression failed (9/10 passed). Restored the
  exact source in `finally`; all ten focused tests then passed. The production
  bundle was built before the mutation; no source preview was running.
- `rtk proxy env PATH=<above> bin/dev.build`: passed, strict/deep ad-hoc seal
  verified. `rtk proxy bin/smoke`: passed bootstrap, cookie, replay/origin refusal,
  heartbeat, graceful quit and listener cleanup. Fresh data was retained at
  `/private/tmp/ccoding-smoke.NX1QV0`.
- Packaged native bridge fixture (`rtk proxy python3 .ccoding/r060o-packaged-native.py`):
  created an app-owned synthetic battle/preparation/capture, read it twice with
  unchanged private proof hashes, reversibly removed the receipt and verified
  refusal without reconstruction, then restored it. Original source bytes,
  index and HEAD stayed unchanged. Fixture retained at
  `/private/tmp/cuckoding-r060o-native-rl_0qvdj`; no provider/inference ran.
- Profile-free schema-seventeen SQLite copy: all fourteen domain table hashes,
  integrity/FKs and schema stayed unchanged through packaged smoke. No profiles
  copied. Proofs/logs remain private under `.ccoding/r060o-*`; copied data is
  `.ccoding/r060o-package-3379524f-7a73-4829-b242-c584293acb53/data`.

Both packaged proofs identify helper SHA-256
`5ebf531762ad50290c6301ea196dc9eb76a35cbb3a63fb1cad0c2bbac8af969b`
and resource-manifest SHA-256
`2533db89b79b2ffdab15418332ecd6e98b6c43cfd996947fda3aa7831bc453c8`.
The initial bridge fixture script failed before child launch because its empty
PATH omitted RTK; it was corrected to capture the absolute RTK path. No existing
workspace was affected.

Five-axis source/diff review checked exact evidence binding, queue/restart/control
races, private file identity, bounded operations, OTP ownership and reuse of the
existing LiveView component. Corrected a misplaced README paragraph. No unresolved
slice findings. Documentation references/whitespace are checked before commit.

No fresh real-browser, real-provider, physical sleep, clean-machine or signed
release acceptance is claimed. The original saved workspace and its profiles
remain untouched. General subprocess containment, other interrupted native/provider
effects and the remaining beta gates stay open in PLAN.

## Local integration

Implementation `400f0bb` fast-forwarded into local `main`; the feature branch was
deleted. Documentation links and `git diff --check` passed. The only unrelated
untracked file remains `Untitled.md.age`, unread/unstaged. No push/publication,
original-workspace launch or paid provider usage occurred. The goal remains active
for the unchecked beta gates in PLAN.
