# R050b worklog — Owned worktree preparation

## Scope and inspection

Started from clean local main `3486bb4` (two commits ahead of origin/main).
Claimed R050b. Applies Ponytail full, local-runner, security-review,
cuckoding-architecture, elixir-phoenix-liveview and quality-gates.
Reuse ArenaGit, its durable command ledger, dispatcher and native process-group helper.
Affected callers: Foundation claims/cancellation/finish, Dispatcher, Repository setup,
Git adapter/native helper, domain/native/LiveView fixtures, docs/README/AGENTS.
No new dependency, migration, provider call or publication.

Acceptance: explicit fresh HEAD/folder-bound consent; exclusive private ownership;
fixed bounded checkout; original files preserved; stale/foreign/late receipts rejected;
partial effects retained, no automatic replay; session-protected visible controls.

`rtk proxy` is used for exact source reads, scripted edits, structured output and
packaging scripts because filtered output would alter source/evidence or these
commands have no RTK semantic wrapper. `rtk proxy /usr/bin/git worktree -h`
confirmed installed Git supports detach/lock/reason (help exits 129).
Reference: existing Apache-2.0 source at `3486bb4`: native
`desktop/src-tauri/src/arena_git.rs:71` (fixed command/process group),
`desktop/src-tauri/src/arena_git/initial.rs:16` (path validation), and
`lib/cuckoding/arena_git.ex:134` (consented request). No peer code copied.

## Verification

- `rtk mix test test/cuckoding/arena_git_test.exs test/cuckoding_web/arena_git_live_test.exs`:
  focused tests integrated into the full suite. Initial UI fixture exposed missing
  test data-root configuration; fixed in `config/test.exs`, without a production fallback.
- `rtk mix quality`: final **160 tests passed**, format/compile with warnings as
  errors, Credo, Sobelow and dependency audit passed. Intermediate Credo complexity
  failures led to smaller consent/receipt predicates. Existing Sobelow warnings
  about generated Mix.lock quoted atoms remain tool diagnostics.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`: passed.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`: passed.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`: final
  **38 passed**, including real detached/locked checkout, original dirty/index
  preservation, hook suppression, filter/symlink/submodule/credential/size/stale-HEAD
  refusal, private parent safety, cancellation after marker creation, deadline,
  retained ownership and existing process-group/descendant cleanup tests.
- `rtk proxy bin/dev.build`: passed, final bundle at
  `desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`. Known OpenSSL
  relocation warnings are followed by explicit local re-signing. No public signature.
- `rtk proxy bin/smoke`: final bundle passed bootstrap, browser cookie,
  replay/origin rejection, heartbeat, graceful Quit and listener cleanup. Final
  fresh data: `/private/tmp/ccoding-smoke.bqxN95`.
- `rtk git diff --check`: passed. Final exact `rtk proxy git diff` checking
  included new files and caught an extra worklog EOF blank line; removed before integration. Python structural check verified 131 local
  Markdown file references with no missing target (not an anchor validation).

## Packaged fixture and browser evidence

Retained QA root: `/private/tmp/cuckoding-r050b-proof-_1z8cgls`.
Fresh packaged smoke seeded an isolated eight-migration DB, copied with SQLite's
backup API. A synthetic registered Arena points only to a newly created disposable
Git repository, with a committed plan, different staged/unsaved bytes and an
untracked canary. No user repository, prior personal DB or provider profile was used.
Older R050a temporary proof files were unavailable; they were not treated as new evidence.

`rtk proxy python3 .../launch.py` starts the actual packaged tray shell, which owns
release bootstrap. Process inspection uses only PID/parent/executable and listeners.
A QA-only one-use DB handoff opens the authenticated UI; no production authentication
change or direct release boot. First shell/BEAM 18537/18539 on port 51233; final
rebuilt shell/BEAM 21342/21346 on port 51564. These identities are historical after cleanup.

CUA verified Repository setup consent refusal; keyboard preparation; visible
progress, owner/runtime and receipt; preserved unsaved Tabula text and disclosures;
actual five-minute expiry; and creation history after restart. At 390×844 and
1280×720, no horizontal overflow. Browser warnings/errors were empty on final inspection.
A discovered focus loss from the disabled submit button was fixed with
`aria-disabled` plus a server guard; keyboard focus now stays on Prepare through
pending and completed states, and duplicate requests while busy do nothing.
Screenshots: `desktop.png` and `narrow.png` under the proof root.

Two separately confirmed preparations created locked detached checkouts of
`cbcb401e229b3a6f446e48ce9ccf28c98ae20c33`. Both contain the committed plan and omit
untracked content. Original staged index SHA-256 remained
`07153272f6bce740cea2e7b5efb05ebc8f9fa78bfac32c9846d868d47d897184`;
original unsaved text and canary remained exact. Each retained command has one
attempt and a matching private marker. Restart comparison against
`before-restart.db` preserved all command/Arena/team/schema rows with no replay;
SQLite integrity and foreign-key checks passed. No migration was added; a historical
schema-upgrade run was unnecessary and was not claimed.

Final native SHA-256: `18a23f3fab3517148f9bb27db8dd7d7d0353a1d16294bfc8fce9961414fbe34e`.
Packaged ArenaGit BEAM: `4d4575498bedd6c6ec45ca2b1101a689ff74b4c5b0fccce4d74dc4219191dbbc`.
Packaged TabulaLive BEAM: `155d9acbc0e7302dfa672e9f7b3872fa085c5da7fb09662be43ebe7f008f0080`.
`rtk proxy python3 .../stop.py` terminated only the verified owned BEAM, then
verified shell heartbeat exit and listener cleanup. This controlled service exit
is distinct from tray Quit (verified separately by bundled smoke). Temporary
browser tab closed and viewport override reset; fixture files/worktrees retained.

## Review, integration and remaining work

Ponytail/security review followed all changed callers. The existing Git adapter,
command ledger, session-protected LiveView and native process group own the new
capability; no new dependency, table, background queue or provider permission.
D019 records the boundary. Native tree/config checks are conservative; built-in
Git attributes may transform checkout bytes, and worktrees share Git metadata.
The same-user host boundary is not a sandbox. Creation never proves future integrity.

Update README/AGENTS and affected architecture/data/flow/security/UI/development/
plan/testing docs in this slice. Integrate the verified feature into local main
and remove its branch. No push, PR or deployment.

Next: R050 battle authority/admission and one permitted provider worktree turn,
then host check receipts and independent Secutor review. Human real-account/model
acceptance, autonomous execution, physical sleep/wake, ports/power assertions,
clean-machine signing and public release remain unverified/unimplemented. This
slice allocates no ports or task power assertions; a simulated expired claim and
no-replay test is not physical sleep acceptance. Site files were unchanged.
