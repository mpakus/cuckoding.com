# R070b — Combined candidate preparation

Claimed from local main `c46eccf` on `feature/r070b-combined-candidate`.
RTK proxy preserves exact source/test/build output. Ponytail full, architecture,
local-runner, workflow, security, quality and Rust lifecycle guidance apply.
`Untitled.md.age` is untouched; no real provider or user Arena effects.

The next parallel workflow needs candidates based on the current reviewed head.
This slice implements that native mechanism and its review/integration consumers;
same-board admission, lane state, conflict repair and controls remain the next
parallel work. No existing Start gains a worker or new grant from this slice.

## Implementation and review

- New private `battle.json` binds newly prepared writer worktrees to their exact
  retained native battle receipt. Older sequential preparations remain readable;
  missing binding grants no new combination authority.
- `combined.rs` rebuilds compatible captured paths on the reviewed head through
  isolated-index plumbing, with a fixed author/message and no merge driver.
  Closed receipts bind source, both bases, original worktree/candidate and new ref.
- Existing review checkout, serialized CAS and retained integration inspection
  verify the new proof. Retained-object verification is separate from the live ref
  check so post-CAS inspection cannot incorrectly require the previous live head.
- New combined operations/consumers have fixed native 60-second and host 65-second
  ceilings. Existing sequential operations retain 15/20-second limits; future
  workflow admission must still enforce its original stage/battle deadline.
- Review traced all native consumers, source/config/ancestry checks, retained
  evidence and cancellation. No migration, dependency, provider grant or Start
  policy changes. Bounded verification may refuse a large/slow repository.

## Verification

- Before implementation the two combination tests refused `invalid_request`.
  Initial implementation exposed the old 15-second ceiling during repeated
  proof/review checkout and a captured-only post-CAS verifier. Both were corrected
  in the new operation path, with the old operation ceilings retained.
- Focused native run: 5 passed in 183.63 s before final budget/tamper assertions;
  disjoint result, new review checkout, CAS/recovery, conflicts, exact binding,
  partial/no-replay and cancellation.
- Mutation: removing the overlap refusal made the pure conflict test fail (exit
  101). Exact source restored in `finally`; final full suite follows.
- `rtk proxy env PATH=<pinned toolchains> mix quality`: 455 passed; strict Credo,
  Sobelow, Hex and dependency audits succeeded. Sobelow's lockfile evaluation
  still emits quoted-keyword warnings; no source warning or vulnerability found.
- Rust format and all-target strict Clippy passed, including a final Clippy run
  after narrowing an unchanged test helper visibility.
- Final `rtk proxy cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`: '94 passed; 5 ignored', 224.85 s. The five opt-in provider/environment checks
  remain unavailable evidence, not passing acceptance.
- `rtk proxy env PATH=<pinned toolchains> bin/dev.build`: successful release/app
  build and strict/deep ad-hoc signature verification.
- `rtk proxy env PATH=<pinned toolchains> bin/smoke`: passed bundled launch,
  session/bootstrap/route checks, replay/origin refusal, heartbeat, graceful Quit
  and listener cleanup. Data retained at `/private/tmp/ccoding-smoke.zyANa9`.
  Packaged helper SHA-256:
  `8bec2aad8d702a3dcd578cc97f966dde5096d0028fe39f863bc022f08f9173ec`.
- Ten affected Markdown files' local links and `git diff --check` passed.

No browser rerun for this native/closed-receipt slice. No real inference, parallel
Start, physical sleep, clean-machine install, Developer ID or notarization proof.

Integration: verified slice committed and merged into local main; branch deleted.
No push or publication. Current app source includes this mechanism; the packaged
artifact was smoke-launched and closed, not left as a user workspace instance.
