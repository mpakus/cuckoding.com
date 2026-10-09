# R050c worklog — Worktree inspection

Claimed from clean main `d37f7c2`, aligned with origin/main at inspection.
Applies Ponytail full, local-runner, security-review, architecture, LiveView,
workflow and quality-gates; menubar-shell for the requested packaged test app.

Acceptance: preparation-bound read-only ownership/index/raw-file observation;
no original file/index mutation, foreign/expired result refusal, no replay;
session-protected controls and honest dated results. Build and leave an isolated
test instance running for the user. No real provider execution or publication.

Reach: ArenaGit/native Git, Foundation claim/cancel/recovery/finish, Dispatcher,
TabulaLive, native/domain/UI tests, README/AGENTS and affected docs. Reuse the
existing ledger/helper/session guard. No dependency or migration.

`rtk proxy` preserves exact source, edits and structured evidence, and runs build
scripts without a semantic wrapper. Reference: repository Apache-2.0 source at
`d37f7c2`: `arena_git.rs:71` fixed runner,
`arena_git/initial.rs:55` descriptor-relative reads,
`arena_git/worktree.rs:85` ownership preparation, and `arena_git.ex:183` request
ledger. No external implementation copied.

## Implementation and review

The existing Git command ledger owns `inspect_worktree_arena_git`, including
exclusion, claims, cancellation, interruption recovery and atomic public events.
Request freezes a same-Arena completed preparation; results bind its key/HEAD/path/
device/inode and reject expired claims. Original source Git observations and Battle
preview are unaffected. Native inspection checks private owner JSON, pinned checkout
identity, immediate source `.git/worktrees` registration, backlink/common directory,
UUID lock and detached HEAD. Bounded index entries and raw blobs/files are compared;
extra names are flagged without opening their contents. No index flags can conceal
modified tracked bytes. Existing descriptor-relative reads are reused.

Ponytail/security review traced all callers and lifecycle lists. No dependency,
migration, provider permission or new queue. D020 documents conservative semantics:
CRLF transformations may report changed, and a filesystem observation is not an
atomic snapshot, execution grant or future-integrity guarantee. The original index,
checkout index, ownership marker and source working files are never written.

## Verification

- `rtk mix test test/cuckoding/arena_git_test.exs test/cuckoding_web/arena_git_live_test.exs`:
  **16 passed**. Includes receipt scope/idempotency, foreign fields, cancellation,
  lease expiry/no replay, sanitized durable events, reconnect and expired sessions.
- `rtk mix quality`: **164 passed**; formatter/compile with warnings as errors,
  Credo, Sobelow and dependency audit passed. Existing Sobelow generated Mix.lock
  quoted-atom warnings remain tool diagnostics.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`: passed.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`: passed.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`: final
  **42 passed**, default parallel harness, 38.41 seconds. New real-Git tests cover
  150-file batching, raw changes hidden by assume-unchanged/skip-worktree, staged-only
  changes, CRLF, modes, extra/ignored files, FIFO/link refusal, missing/replaced
  ownership, detached HEAD/lock/backlink/config refusal, cancellation/deadlines and
  source/index/marker preservation.
- Initial full native runs (parallel and `-- --test-threads=1`) had **39 passed,
  3 failed**: existing 100 ms cancellation / 250 ms deadlines expired before fixture
  child markers or login responses. Test-only fixes wait for the child marker before
  cancellation and allow three seconds for startup/timeout fixtures. Production
  deadlines are unchanged. Final Clippy and full default harness pass; no failed
  run is counted as passing.
- `rtk proxy bin/dev.build`: passed; `rtk proxy bin/smoke`: passed launch/bootstrap,
  browser cookie, replay/origin refusal, heartbeat, graceful Quit/listener cleanup.
  Fresh smoke root `/private/tmp/ccoding-smoke.Lba38Q`. Known OpenSSL relocation
  signature warnings are followed by explicit local re-signing. After packaging,
  only test-fixture timing and documentation changed; production source stayed fixed.
- Exact `rtk proxy git diff --check`: passed; 134 local Markdown file references
  resolved (not an anchor validation). No schema migration or site change.

## Packaged real Git and browser evidence

QA root: `/private/tmp/cuckoding-r050c-qa-ogra3qgs`. Fresh smoke data copied into an
isolated fixture; a clearly synthetic registration points only to a newly created
disposable dirty Git repository. Initial QA seed had an INSERT arity error; its
transaction rolled back and was corrected. No normal user database or provider
profile was used. Native shell owns the release handshake; no direct release boot.
A one-use QA handoff was inserted only into the isolated DB for browser inspection.

Real preparation `8b27d688-4f23-4101-8425-f1e53389a41e` froze commit
`1a33f8803e76c5e992afa728f1164f2c9f6ae9e6`. Packaged inspection reported unchanged,
then changed after editing only the disposable checkout, then cancelled. All three
commands retained one attempt. Source dirty text, source index, checkout index and
owner marker hashes stayed exact; untracked canary stayed in the source. No provider
call, reset, prune or remote operation occurred.

CUA verified keyboard activation, progress, Cancel, dated results, unchanged/changed
states, preserved unsaved Tabula name/disclosure and focus on Inspect through updates.
At 1280×720 and 390×844 no horizontal overflow; browser warnings/errors were empty.
Screenshots `desktop.png` and `narrow.png` are retained in the QA root. Temporary
viewport override was reset. Source inspection stays separate from worktree results.

QA restart used verified owned executable/PID/parent/start identity and loopback
listener. First shell/BEAM 99646/99649 on port 63226, restart 948/951 on 63633;
both QA runs are now stopped with listener cleanup verified. Commands, Arenas,
team/schema rows and historical events matched `before-restart.db`; only expected
`shell.authorized`/`browser.authorized` events were added. No command replay. SQLite
integrity/foreign keys passed. QA browser tab closed; retained artifacts were not deleted.

## Running test app for the user

Separate user test root: `/private/tmp/cuckoding-r050c-proof-vvr7u4wp`.
The built bundle was copied to `Cuckoding.app` there so subsequent builds do not
replace a running binary. Data lives in its `data/` subdirectory, separate from
normal Cuckoding data. The user began an account sign-in in this instance while QA
was underway; it was left intact and verification moved to the second fixture.
This is not evidence of completed real-account/model acceptance.

At final verification: native shell **96007**, BEAM **96023**, both started
2026-10-08 23:08:18 local time, listening on **127.0.0.1:62885**. The tray app and
browser dashboard remain running for the user. `Open Cuckoding Test.command` in
that root reopens the isolated profile after quitting its current tray instance;
this retained temporary test directory is not a public installation. Process
inspection used executable/parent/start identity/listeners, never raw argv/env.

Native SHA-256: `ea4def60b6902e30db3176d4c9b967a470abc2027b8f2076ac3e932c7e59c542`.
ArenaGit BEAM: `99814c17b1d6cdfd7f2c381af636e64a6dfc0aff0738c5753e684d935309651f`.
TabulaLive BEAM: `e0e20d7a32744cf3158ca1eb51a72317095ddeebd94dd66686b9bd08b841f2b3`.
Copied native binary matches the default packaged output. `proof.json` contains
local identities; `running-test.png` records the open dashboard. A direct IAB home
navigation was client-blocked; the existing authenticated dashboard link succeeded.

## Integration and handoff

Update README, AGENTS and architecture/data/flow/security/execution/UI/development/
plan/testing/decision docs with the verified boundary. Local integration uses a
fast-forward merge into main and deletion of the merged task branch. No push,
PR, deployment or public signature is authorized or attempted.

Next remains R050 bounded Start authority/admission and a permitted provider
worktree turn, followed by host checks and independent Secutor review. This slice
does not implement autonomous battles or provider repository execution. Human
real-account/model acceptance, physical sleep/wake and clean-machine signing remain
open. Tests use synthetic provider fixtures; no new ports/power assertions or
migration were introduced by worktree inspection.
