# R050d1 — Exact task candidates

Ponytail full 5.2.0 MIT, architecture, local-runner, agent-adapter,
security-review and quality-gates apply. All commands use RTK; proxy retains exact
source/protocol output. Reuse the existing fixed Git transport, pinned descriptor
reads and worktree registration validation. No new dependency or copied source.

Acceptance: freeze only exact declared task edits in a retained candidate;
prove unaffected bytes and original checkout preservation; never claim a role
report or candidate capture proves completion. This is a host prerequisite of the
one-button execution loop, with no new mandatory UI step.

## Verification

- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked candidates_`:
  2 passed (10 rejection scenarios plus successful capture/verification). Initial
  test compilation used string methods on byte output; corrected the fixture
  assertions before the passing run.
- `rtk mix test test/cuckoding/arena_git_test.exs`: 12 passed.
- `rtk mix quality`: 208 tests passed; format/compile/Credo/Sobelow/audit passed.
  Existing generated Mix-lock quoted-keyword warnings remain.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`: passed.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`: 62 passed,
  2 explicitly consented provider tests ignored. These ordinary tests perform no provider inference; the separately authorized
  real-account result is recorded below.
- `rtk proxy bin/dev.build`: packaged Cuckoding.app successfully, including Decimal
  3.2.0 and the R020n task transport. Expected relocation/ad-hoc signing warnings;
  this does not establish notarization or clean-machine release acceptance.
- `rtk proxy bin/smoke`: passed bundled launch, bootstrap/browser session, replay
  and origin refusal, authenticated routes, heartbeat and graceful Quit/cleanup.
  Final clean-release smoke root: `/private/tmp/ccoding-smoke.MolB07`.
- `rtk git diff --check`: passed. Documentation references and shipped/target
  boundaries checked against the changed source. No site changes.

## Running artifact and retained data

Verified the prior shell PID/start identity, child BEAM, working directories and
loopback listener, found no active commands, then gracefully terminated the owned
service. Its shell exited via heartbeat; listener cleanup passed before packaging.
No provider or unrelated process was stopped. SQLite backup and proofs retained
at `/private/tmp/cuckoding-r050d1-proof-q59rzi8h`.

Relaunched the rebuilt `Cuckoding.app` with the exact saved test data root
`/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data`; unchanged saved launcher.
At verification: shell 22157, BEAM 22159, loopback port 53954. Start identities and
native binary hash are in `proof.json`; these are observations, not future PID
ownership evidence. All 11 durable application table hashes matched before/after,
including agents, workspace, teams, Arenas, tasks and commands. The running bundle
loads Decimal 3.2.0. The initial package still contained an unused Decimal 3.1.1
directory because both Mix and Tauri overlaid their previous generated output.
Corrected `bin/dev.build` to refuse running/linked releases and bundles, then
recreate both generated trees. The running-bundle refusal was verified before
shutdown. A fresh build passed; all three release/resource/bundle lib directories
now contain only `decimal-3.2.0`. The second graceful shutdown exceeded the
15-second observation window; follow-up verified both owned processes and the
listener gone without forced termination.

## Handoff

Candidate capture is a host primitive, not reviewed integration or a new UI setup
step. Start admission, declared-check execution, stage dispatch, independent
Secutor review, recovery and parallel workers remain open. No DB migration,
remote push or deployment. The user then signed in a new independent Codex `c2`
connection. That intentional action changed agents/workspace/commands; a new
SQLite backup and table-hash baseline are retained in `after-user-login.db` and
`data-after-user-login.json`. Do not compare these authorized changes to the older
baseline or rewrite the user's team.

The first of the two approved real file-tool turns used c2 and GPT-6.1 Sol. It
finished after 7.7 seconds with a blocked role report: the supplied tool returned
`code-mode host is disabled`. No host file-tool call or file mutation occurred.
The read fixture assertion failed, so the write turn has not run. Receipt:
`/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data/probes/00000000-0000-4000-88de-297ef1e92e48-task-acceptance/receipt.json`.
The earlier legacy-profile attempt returned not_connected before inference.
Real tool acceptance is still open; investigate model tool routing before
enabling Start. The remaining approved write turn must run alone, not silently
repeat both tests.

Final clean-build launch: shell 25001, BEAM 25003, loopback 54500, saved data root
and launcher unchanged. All 11 durable tables match the after-user-login backup.
Final native hash/start identities are in proof.json. No existing Arena task ran.
