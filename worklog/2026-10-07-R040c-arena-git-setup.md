# R040c — Arena Git setup

Claimed clean `main` at `60c7bee`; branch `feature/R040c-arena-git-setup`.
Acceptance: explicit bounded inspection of registered folders; fresh-observation
confirmation for missing-repository initialization; no file staging/commits or
agent execution; durable cancellation/interruption, tests, docs and local merge.

Ponytail 4.13.0 (MIT), local-runner, security-review, LiveView and quality-gates
applied. Reuse native `probe.rs` process-group ownership, `NativeFolder` clean Port
transport, `Arenas` identity validation and `Foundation` command/claim/event flow
at `60c7bee`. No external source copied or dependencies added.

Primary Git interface references: [git-init](https://git-scm.com/docs/git-init),
[git-config](https://git-scm.com/docs/git-config),
[git-rev-parse](https://git-scm.com/docs/git-rev-parse) and
[Git environment](https://git-scm.com/docs/git). Cuckoding additionally bounds
metadata, rejects external config/layouts, clears inherited environment, prevents
automatic replay and binds mutation consent to the registered directory identity.

RTK proxy exceptions: exact Python fixture/build/inspection scripts, fixed Git
protocol experiments, and native build environment/streaming semantics. Runtime
Git uses an exact-output bypass for machine-readable results, never shell text.
Reference locations: `desktop/src-tauri/src/probe.rs:14` (owned group),
`probe.rs:25` (non-reaping exit check), `lib/cuckoding/arenas.ex:193`
(registered folder validation). The native Port transport was renamed to
`NativeHelper` and reused rather than copied. All repository sources are under
the project license; no peer source was needed for fixed Git builtins.

## Delivered

- Explicit standalone Git inspection: missing, unborn or a validated HEAD commit.
  No working-file reads/staging/commits, remote operations or execution grants.
- Fresh-observation and directory-identity-bound init confirmation, exclusive
  `.git` creation on `main`, empty templates, closed public receipts and audit.
  Six migrations remain sufficient; commands own observations durably.
- Fixed system Git, cleared environment/config, bounded metadata/config/output,
  unsafe external-layout refusal, pinned root handle and native owned groups.
- Cancellation and uncertain interruption never replay; shared helper transport
  handles broken pipes and nonzero/unacknowledged cleanup without reporting success.
- Collapsed Repository setup within the existing Tabula screen; elapsed state,
  keyboard confirmation/Cancel, durable result, preserved disclosures and drafts.
- README, AGENTS, plan, architecture/data/flow/security/execution/UI/development/
  testing docs updated. Initial-commit and orchestration gates stay open.

## Verification

- `rtk mix format` and `rtk mix compile --warnings-as-errors` — passed.
- `rtk mix test test/cuckoding/arenas_test.exs test/cuckoding/arena_git_test.exs test/cuckoding_web/arena_git_live_test.exs`
  — 13 passed. Includes fresh/stale/foreign consent, command replay, closed
  receipts, cancelled/expired claims, expired browser sessions and reconnect.
- `rtk mix quality` — final **93 passed**, formatter/compiler passed, strict
  Credo no findings, Sobelow completed, dependency audit no vulnerabilities.
  Existing Sobelow quoted-keyword lockfile warnings remain tool diagnostics.
  Earlier runs caught a missing test environment, receipt-function complexity
  and a cancellation broken-pipe race; fixed and rerun successfully.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml` and
  `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`
  — passed. `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`
  — **27 passed**. Real Git fixture checks preserve document/index/config bytes,
  reject unsafe metadata and mismatched pinned handles, and kill owned descendants
  on cancellation/deadline while preserving an unrelated peer process. An added
  lock test failed under parallel execution while its temporary lock was still
  held; explicit unlock before continuing fixes the fixture race. No production
  serialization or safety guard was weakened.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r040c-target bin/dev.build`
  — passed. Isolated output preserves the user's existing app bundle. Xcode
  install-name signature warnings are followed by the build's ad-hoc signing.
- `rtk proxy python3 /private/tmp/cuckoding-r040c-proof-96vy_fjv/verify-package.py`
  — fresh and copied-R040b packaged smoke passed: bootstrap, browser cookie,
  handoff replay/origin refusal, heartbeat, graceful Quit and listener cleanup.
  Six migrations, integrity/FKs passed; prior teams/Arenas/boards/tasks/revisions
  preserved exactly and source DB hash unchanged. Copied Arena paths were not used.
- CUA against the isolated packaged release at **127.0.0.1:51822**: synthetic
  temporary Arena, create board, enter unsaved task, Inspect Git, refuse unchecked
  init (no `.git`), keyboard Space/Return confirmation, observe initialized result,
  save preserved task and reload the dated observation. Desktop and 390×780
  layouts inspected; narrow document/viewport widths both **390px**. Actual Git
  effects were confined to the new fixture project.
- Browser registration was seeded into the isolated fresh DB and used a
  one-minute test-only handoff. Native authentication is separately smoke-tested;
  this does not establish real-provider or first-install acceptance.
- `rtk proxy python3 /private/tmp/cuckoding-r040c-proof-96vy_fjv/verify-browser-result.py`
  — passed: document bytes unchanged, `main` HEAD with no ref/commit/index/hooks,
  observation-bound init, six closed lifecycle events, retained task, integrity/FKs.
  Verified owned shell **16791** / release **16794**, sent SIGTERM only to that QA
  release, observed shell exit and listener **51822** closure. Packaged restart/
  graceful-Quit smoke preserved observations/drafts without replay. Other apps
  were not signalled; browser tab closed and viewport restored.

## Artifact and limits

Bundle: `/private/tmp/cuckoding-r040c-target/release/bundle/macos/Cuckoding.app`.
Evidence: `/private/tmp/cuckoding-r040c-proof-96vy_fjv` (harnesses, smoke/restart
logs, source copy, fixture DB/project and identity JSON). Screenshots:
`/private/tmp/cuckoding-r040c-desktop.jpg`, `/private/tmp/cuckoding-r040c-narrow.jpg`.
The browser-tested native executable SHA-256 was
`b83faf8fd45288037c916a0e351607339d789d6bdad773a8d0d179ca20be85cc`;
the final build identity is recorded below after the last strict input-guard check.

Advisory locks do not exclude ordinary Git or malicious same-user metadata races.
Forced helper death can make cleanup uncertain; partial `.git` is retained and
must be inspected. This is not a sandbox or clean-worktree/execution readiness
claim. `/usr/bin/git` tested as `2.54.0 (Apple Git-157)`; Apple command-line tools
remain a prerequisite. No new dependencies or migrations.

No real-provider, clean-machine/signing, physical sleep/wake or autonomous-battle
acceptance. Simulated sleep-sized lease gaps passed. No push, Pages deployment or
replacement of the user's running app. Next: initial-commit preview/consent,
then agent planning with source/spec provenance and execution grants.

Final verification also rejects a forged inspection carrying init-consent fields;
this is a strict input guard covered by the final 93-test suite. Rebuilt the bundle
and ran `rtk proxy python3 /private/tmp/cuckoding-r040c-proof-96vy_fjv/final/verify-package.py`:
fresh/prior smoke and all retention checks passed again. Native, helper and UI
bytes match the browser-tested build; only the ArenaGit BEAM changed for that guard.
Final `final/identity.json` SHA-256:

- Native: `b83faf8fd45288037c916a0e351607339d789d6bdad773a8d0d179ca20be85cc`
- ArenaGit: `bb7d39b9954f2be8bff7a748d38ca1a3fae8f63287442b2778eec0c141162608`
- NativeHelper: `a0312385016650471de031912e881e0c45e3b93b70705203ecc52294c624f30e`
- TabulaLive: `afe6e15b0294c253e42212f90121ff2fdd2c2ecc3331d2063965894eb9fc49ba`
- Prior DB source: `7b1467cbc4bcdac8bfb76c566956315ea3e0f6d38361778b3646ba091f3b3a8e`

`rtk proxy python3 -` Markdown path/anchor checker — **22 documents, 93 local
links/anchors passed**. `rtk git diff --check` — passed. Static site unchanged;
no site gates rerun. No new plugins needed.

## Local integration

`2a08564` — `feat(arenas): Add consented Git inspection and initialization`.
`rtk git switch main` and `rtk git merge --ff-only feature/R040c-arena-git-setup`
passed. `rtk git branch -d feature/R040c-arena-git-setup` deleted the merged branch.
This integration-record update changes no tested application bytes. Local main
only; remote publication, Pages and the user's running build are unchanged.
