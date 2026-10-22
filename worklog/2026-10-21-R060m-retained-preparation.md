# R060m — Retained worktree preparation checkpoint

Following local main `803184e`. Ponytail full 5.3.2 (MIT), architecture,
workflow/kanban, security-review, local-runner, LiveView, quality-gates and the
Rust router/lifecycle/concurrency/CLI skills apply. RTK prefixes every shell
command; proxy preserves exact source/protocol and audit output. No dependency
or new runtime/provider grant is planned. `Untitled.md.age` stays untouched.

Read the native worktree prepare/receipt/battle-tag/inspection code and the
existing retained-integration/provider-closure dispatch/settlement paths first.
D041 records the new precise boundary before implementation. Acceptance is in
the task file; the overall beta goal remains active.

Implemented the fixed native read in `arena_git/worktree/battle/preparation.rs`,
reusing private descriptor reads, repository locking and raw-byte inspection.
No provider/command grant, schema, dependency, user checkout or historical snapshot
changed. Native fixtures cover 15 scenarios including same-byte symlink receipts,
missing/tampered/foreign evidence, changed source/checkout, cancellation/deadline
and repeatable reads with unchanged source index/HEAD/ref/untracked/owned bytes.

New Starts freeze `retained-preparation-v1`. Existing supervised exclusive recovery
arms only one interrupted writer preparation with all other attempts settled and
no preexisting Stop/timing fence. Closed exact observations keep the original
Interrupted attempt and append host UTC time; verified in-budget results advance
to Paused for explicit Resume. Expiry or a timing fence racing the completed read
retains Stop closure only. Pending-read authority and settlement authority are
separate, so cancellation does not discard already-verified closure or accept work.
The shared Git normalizer now preserves explicit false/malformed cleanup instead
of dropping it before recovery projection. Missing flags retain compatibility.

Review traced native dispatch/request/load/inspection/group closure, host adapter,
SQLite arm/settle/Stop/Resume/expiry/timing, wave state, supervised coordinator loss
and the guarded existing Inspect component. Feature validation stays in the small
PreparationRecovery module; existing transactional advancement owns state. No
new unmanaged process or frontend framework. All new functions have callers;
no orphaned surface or speculative subsystem. Corrected restart copy to describe
the retained checkpoint instead of saying no interrupted stage existed.

Verification (all shell calls RTK-prefixed; proxy preserves exact output/logs):
- Initial red native valid-read assertion failed before the new operation.
  First host regression failed before domain methods existed; fixture discovery
  metadata was then corrected to a separate synthetic home/source.
- `rtk proxy env PATH=<pinned> cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`:
  **95 passed, 5 ignored** (`.ccoding/r060m-native-tests.log`); ignored real-provider/
  sandbox acceptance was not run. Rust format and strict all-target Clippy passed.
- Focused host/domain/executor/LiveView/Git tests: **91 passed**.
- Final `rtk proxy env PATH=<pinned> mix quality`: **507 passed**, format/compile,
  strict Credo (1,963 modules/functions), Sobelow and both dependency audits passed
  (`.ccoding/r060m-quality-final.log`). Existing migration redefinition and lockfile
  quoted-keyword audit warnings are retained; no warning suppression added.
- Deleted the exact recovered-head comparison for one controlled mutation. The
  foreign-head regression failed (exit 2); finally restored identical source bytes,
  SHA-256 `c35595f2ae2e37b2f4b86dfbb6bf4e99740ce38019dae01e23d494c4a038ebd1`.
  Final quality recompiled the restored source.
- `rtk proxy env PATH=<pinned> bin/dev.build` passed after final product edits;
  complete ad-hoc strict/deep signature verified. Helper SHA-256:
  `3e2c265b70d1553cd73ffbdd055c5ca609d4e91c168471a76a6d0b22d42d3f09`.
  `.ccoding/r060m-build-final.log` records the build. This is not notarization.

Browser check was attempted on source port 51887 with a clearly stopped visual
fixture in `.ccoding/ui-dev`, not provider authority or a real Arena run. The
native Chrome control timed out while opening the Arena; no completed panel/
narrow screenshot or keyboard walkthrough is claimed. LiveView tests do cover
public-only dated rendering, reconnect, no Start/Resume from historical observation
and foreign-board isolation. Full browser acceptance remains R080/R100.

Before source launch, verified canonical private marker, free shell lock, idle
commands/battles, fifteen migrations and SQLite integrity/FKs. Preserved
`.ccoding/r060m-ui-before-c7efc5f0-62ec-41d8-82fa-af191374ae1d.db`, SHA-256
`1b0f35dd2b209a2613066e6992c2d8d3504da96cc31a8fac0be41ed7bc57fe98`.
Verified launcher PID/start/executable/cwd/lock and backend/listener, backed up
again to `.ccoding/r060m-ui-before-stop.db`, then normal TERM to only owned launcher
15248. Launcher/backend 15250 exited, port 51887 closed and lock was free. A cleanup
attempt correctly hit the immutable battle trigger; no trigger was removed or
archive restored. The stopped synthetic record `6cd87ab3-104d-4a5d-a7d8-df66776d8c8f`
remains labelled `ui_visual_fixture_only` in development data, with no tasks or
attempts. Original Arena/board/draft/team/agent rows remain equal to backup.
The old saved user root, private profiles and untracked `Untitled.md.age` remain
untouched. No provider allowance, push or publication was used.

The Rust external child-test module follows the official module-resolution rules:
https://doc.rust-lang.org/reference/items/modules.html . No peer source was copied.

Final bundled smoke passed with normal quit/listener cleanup; retained root
`/private/tmp/ccoding-smoke.7q14Mo` (`.ccoding/r060m-smoke-final.log`). Source
`bin/dev.server --port 0 --no-open --smoke` passed session/reload/origin/CSP checks
on port 52232 and stopped normally. Source/ad-hoc package evidence remains
separate from signed release, provider, physical sleep and timed setup acceptance.
Markdown local-link checks and `git diff --check` passed.

Committed as `1c653ac`, fast-forwarded into local `main`, and deleted
`feature/r060m-retained-preparation`. Nothing was pushed/published. The overall
beta goal remains active; this task completes only its specific retained checkpoint.
