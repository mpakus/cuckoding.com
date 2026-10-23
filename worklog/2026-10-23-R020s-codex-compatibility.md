# R020s — Installed Codex compatibility

Implemented and verified; local integration pending. Branch
`feature/R020s-codex-compatibility`, base `bbdec5e`.
Ponytail full 5.3.2 (MIT); adapter, local-runner, security, OTP/Rust and quality
guidance. No inference, user profile/credential access, push or publication.
Unrelated `Untitled.md.age` remains unread and unstaged.

R060q observed the signed desktop executable at 0.163.0-alpha.11.2 while task,
isolation and checks require exactly 0.162.0-alpha.17.2. Verify the new exact
cohort without changing grants or inferring compatibility from version numbers.
Keep old setup-only versions; actual receipt version must match the captured
request version even if both become supported.

Sources: official [app-server lifecycle and permission profiles](https://learn.chatgpt.com/docs/app-server)
and [permissions](https://learn.chatgpt.com/docs/permissions), fetched 2026-10-23.
Thread creation and effective configuration are distinct from turn/start inference.
The fixed setup preflight also covers account/read and login-start/cancel without
opening a browser or signing in. No other provider method is authorized here.

## Implementation and review

Native `codex_versions` shares the two exact execution cohorts between isolation
and command checks. Host Codex keeps setup-only baselines separate. Isolation
freezes the actual observed version and requires the same native receipt version,
executable identity and version-command ID at settlement. Historical facts remain
unchanged. The cross-cohort regression rejects a receipt for the other supported
version and then accepts the correct version for each cohort.

Explicitly disable the newer action/installation/delegation/daemon defaults for
setup and constrained turns. Code Mode remains enabled only for the existing
host-task-tool grant. OS sandbox checks disable daemon auto-start; no filesystem,
network, subprocess or provider grant was widened. Transport/proxy behavior is
unchanged. Test-only policy preflight checks effective configuration and an
ephemeral thread without turn/start; it is absent from the release CLI/API.

Reviewed the connected setup/configuration, task/no-tools grant, OS canaries,
host settlement, battle readiness and LiveView diagnostic paths. No new mandatory
setup check, dependency, migration, model/account fallback or runtime grant.

## Verification

- Signed installed desktop binary: exact **0.163.0-alpha.11.2**, strict signature
  check and offline schema/feature listing in private
  `.ccoding/r020s-schema-uvo7syt6`. Empty HOME/CODEX_HOME/TMPDIR; no existing profile.
- Exact `connection::task_turn::tests::offline_codex_policy_preflight` with
  `--ignored --exact`: passed task/no-tools effective policy and ephemeral thread
  metadata on the installed desktop binary, with verified cleanup and no auth file.
- Exact `connection::task_turn::tests::offline_codex_setup_preflight` with
  `--ignored --exact`: desktop and setup-only **0.146.0** each passed account
  inspection plus login-start/cancel. No browser/link output, sign-in or inference.
  The final runs explicitly unset `CUCKODING_TEST_PROFILE`.
- Exact `isolation::tests::real_codex_two_workspace_isolation` with
  `CUCKODING_ISOLATION_CANARY=fixture`: passed against the new desktop cohort.
- Exact `project_checks::tests::offline_single_process_sandbox_canaries`:
  passed in **91.52 seconds** against that cohort, fresh debug helper and actual
  RTK `/opt/homebrew/bin/rtk`. Fork/spawn/setsid, paths/network, cancellation,
  output/timeout and group cleanup remain bounded by the existing single-process
  grant. This does not enable Mix/npm or prove arbitrary child-session containment.
- `rtk mix quality`: **573 passed**, strict Credo (2,189 modules/functions, no
  issues), audits and Sobelow passed, terminal exit zero. Existing audit keyword
  and intentional migration/fault-fixture warnings remain; none suppressed.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`:
  **101 passed, 7 ignored**, 226.13 seconds. The two added ignored tests require
  an explicitly selected executable; real-provider inference remains unrun.
- After preserving proxy transport and extending the setup preflight, final
  `connection::` regressions: **23 passed, 3 ignored**; exact desktop/legacy
  preflights, Rust format check and locked all-target Clippy with warnings denied
  all passed. The full Elixir source was unchanged after its quality run.
- Mutation removed the exact receipt/request version comparison: the focused
  regression failed; exact source restored before the final passing checks.
- Local Markdown targets: **262** verified in affected docs/task/worklog;
  whitespace checks passed.
- An initial broad `real_codex_ --ignored` filter selected the consented task
  test, which refused at its missing `CUCKODING_TEST_PROFILE` guard before any
  provider launch or profile access. No inference occurred. New tests now have
  `offline_codex_` names; documentation requires exact names and unset profile.
  Initial missing fixture version initialization, wrong RTK path and setup-status
  expectation were corrected before the passing final checks.

`rtk proxy bin/dev.build` passed. Strict/deep sealed local-preview build receipt
**f17e7e0a-c6b7-4f8b-a4bf-42e937d11e06**, source `bbdec5e` plus then-uncommitted
inputs, schema seventeen. Source digest
`1e56becba57e8fedfdb703be76526d61328acfd946c9f313807c5711ad3ba8de`;
helper `99f7e910d7ce888e57c82a1f062f4617163b7b8c23f6cb599f9888324c6c4584`;
resource manifest `b1227e4e1b5e7b2e71a3f90b5db324686bab4721553123abecad8a65c25438ff`.
The dirty source observation is intentional; this is not a signed release tag.

`rtk proxy bin/smoke` passed bundled launch/bootstrap/browser cookie/handoff replay
and origin refusal, heartbeat, graceful quit and listener cleanup. Fresh data
retained at `/private/tmp/ccoding-smoke.BRKWLo`; read-only SQLite integrity/FKs,
seventeen migrations and the released shell lock verified after quit. No user
workspace/profile was copied or launched. No visual browser acceptance is claimed.

Private logs: `.ccoding/r020s-quality.log`, `r020s-native.log`, `r020s-mutation.log`,
`r020s-final-{desktop-setup,legacy-setup,connection,clippy,fmt}.log`,
`r020s-build.log`, `r020s-smoke.log` and immutable build receipt.

Real-account execution/review/parallel acceptance on this exact cohort, remaining
providers, general subprocess checks, broader recovery, physical sleep and release
signing/clean-machine acceptance remain open. No inference, push or publication.
