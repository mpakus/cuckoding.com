# R050f — Task-owned verification

User correction: verification belongs in tasks generated from specs; separate Arena check configuration must not block the ordinary flow.

Claimed `tasks/R050f-task-verification.md` on `fix/R050f-task-verification` from clean main `58ee397`. Read current domain, executor, UI, planning contract, core docs and relevant Ponytail/workflow/adapter/security/quality skills. Reuse immutable task criteria and the existing review loop; no new subsystem or dependency.

RTK: use `rtk proxy` for exact source reads, pinned asdf commands, Python edits and native build scripts where output/argv semantics must be preserved.

## Verification

- `rtk proxy asdf exec mix test test/cuckoding/battles_test.exs test/cuckoding/battle_executor_test.exs test/cuckoding/planning_test.exs test/cuckoding_web/battle_live_test.exs test/cuckoding_web/project_checks_live_test.exs`: 48 passed.
- `rtk proxy asdf exec mix format`: passed. Initial `mix quality` found two test-only Credo findings (nested alias, fixture branching complexity); corrected both.
- Final `rtk proxy asdf exec mix quality`: 247 passed; format/compile, Credo and audit passed. Sobelow retained its existing quoted-key warnings while reading `mix.lock`; scan/audit reported no vulnerabilities.
- Native commands use `rtk proxy env PATH=/Users/mpak/.cargo/bin:/opt/homebrew/bin:/usr/bin:/bin cargo …` with pinned Rust. `fmt --manifest-path desktop/src-tauri/Cargo.toml --check` and `clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings` passed.
- `cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked connection::model_check::tests` under the same RTK/pinned prefix: 6 passed. Full `cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`: 70 passed, 3 opt-in tests ignored. The account test and offline sandbox canaries were not rerun; no native process/permission behavior changed.
- `rtk proxy env PATH=/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/Users/mpak/.cargo/bin:/opt/homebrew/bin:/usr/bin:/bin bin/dev.build`: passed. Existing Tailwind/OpenSSL signing steps completed. `rtk proxy bin/smoke`: passed bundled authentication/routes/heartbeat/quit/listener cleanup; isolated smoke data retained at `/private/tmp/ccoding-smoke.GzUJxy`.
- `rtk proxy git diff --check` and changed-Markdown local-link validation: passed.

## Implementation and review

`arena-loop-v2` makes task criteria the default verification contract. Only that exact snapshot version with `checks: []` skips command resolution/stages. Independent candidate/final reviews still require matching model/session/candidate, retained criteria and a successful host inspection tool receipt. No passing command receipt is fabricated. Configured commands keep their failure/review gates; old v1 snapshots cannot inherit the new exemption. Planning asks for expected outcomes and concrete checks inside each task without treating those instructions as executable policy. Missing required runtime evidence must block review. Existing task/check/team revisions are not rewritten; no migration/dependency/grant expansion.

Fixtures exercise the complete two-task no-command loop with forced review returns, preserved criteria, final review, absent command calls/receipts, blocking missing evidence, rejecting a no-inspection review, and legacy/configured-command gates. Automatic card import preserves verification prose exactly. Native prompt fixtures keep the no-tools scratch grant. These are fixture results, not real provider acceptance.

## Running artifact and preserved workspace

Read-only inspection confirmed old native PID 97298 / BEAM 97328, start identities and loopback port 62343 belonged to the saved test launcher. No active battle or setup command was present. SQLite backup retained at ignored `.ccoding/r050f-validation/before-rebuild.db`. Sent SIGTERM only to the identified native PID; its BEAM exited through the shell heartbeat timeout. Verified both were gone before building. No unrelated provider process was stopped.

Reopened the unchanged `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/Open Cuckoding Test.command`. Current native PID 7658 / BEAM 7659 started 2026-10-13 15:36:47 CDT, from the rebuilt `Cuckoding.app`; the BEAM cwd remains `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data`, listening only on `127.0.0.1:63127`.
Native helper SHA-256: `7491cd6bc4dc4e63e9bf094c8c3b0539311b2d9dba1639274728f1daec98695d`.

Compared all rows with the backup: workspace (1), named agent connections (2), team revisions (2), adoptions (0), Arenas (2), boards (2), task drafts/revisions (2 each), command-check revisions (0) unchanged. SQLite integrity is `ok`, no foreign-key failures, 10 migrations and no battle created.

Chrome inspection of the user's exact Arena on the new port confirmed the task-verification copy and removal of the mandatory check setup/link. The remaining blockers are its existing Cursor Implementor/Summa Rudis assignments (execution currently Codex-only) and a stale Codex catalog. Bindings were preserved, no provider inference was launched. The first native typing navigation dropped characters; replaced the address using paste and verified the exact route. Screenshot retained locally at `.ccoding/r050f-validation/arena.png`. Narrow rendering was not rechecked; no layout/CSS changed.

## Handoff

Docs, README and AGENTS describe the new default and unchanged execution limits. Local integration only; no push or publication. Further beta work remains real-account battles, Cursor/other provider execution, general toolchain commands, recovery and parallel workers. Do not imply that task verification prose can run unsupported shell tests.
