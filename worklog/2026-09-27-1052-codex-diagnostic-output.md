# 1052 — Codex diagnostic output

Claim task 1052 only. Started from clean `main` at
`3c68783f7f8ae39f0d400c74e39b3a3f6774197f` on
`fix/1052-codex-diagnostic-output`. The supplied log is treated as a bug report;
the optional question about its intended focus has not received an answer.

Acceptance: reproduce and fix the shared parser's rejection of native Codex
diagnostic lines, preserve strict structured validation and capture limits,
keep diagnostic content out of activity/usage/results, and replay the retained
artifact without modifying live data or starting provider work.

## Analysis and references

Applied Ponytail 4.10.0 (MIT), full mode, agent-adapter, security-review, and
quality-gates. Read the task, parser/tests, all parser callers, runner stream
capture, and adapter documentation; required product/architecture/database/
flow/security/environment documents were read during the preceding work.

The live database was opened read-only. The reported planning run exited zero
but persisted `task_intake.failed` / `malformed_output`, a blocked run and zero
proposals. The retained 195,500-byte artifact contains valid JSONL plus the
known stdin prelude and two UTC-timestamped `ERROR codex_core::tools::router:`
diagnostics. Its final agent message contains 11 proposals. Interleaved stderr
is expected because `LocalProcessRunner` uses `:stderr_to_stdout`. Both the
result decoder and activity/usage readers previously rejected those lines.
Full command arguments, provider text, and private project content are not
copied into repository fixtures or this log.

`rtk xerj search --prefix cuckoding-project-v7 -k 5 'Codex JSONL output_parser stderr tracing diagnostics malformed_output'`
failed: no node reachable at localhost:9200. Used repository search and the
pinned local peer instead. Inspected Apache-2.0 license and
`vibe-kanban/crates/executors/src/executors/codex.rs:638-681` at the pinned
`735654971bd396aa97b65166955678e4c34f8bf8`: that app-server transport pipes
stderr separately. No peer code was copied. Cuckoding retains its existing
redacted process artifact and filters only the recognized diagnostic envelope
at the shared parser boundary. Diagnostics remain untrusted and grant nothing;
structured output still passes the existing task/review/controller validators.

## Verification

- `rtk env -u CR_PAT mix test test/cuckoding/adapters/output_parser_test.exs`:
  reproduced the failure first (8 tests, 1 failure, seed 981153); passed after
  the fix (8 tests, 0 failures, seed 756603). The added regression covers result,
  activity, usage, diagnostic privacy, malformed JSON, unknown diagnostics,
  provider isolation, row limits, and byte limits.
- `rtk env -u CR_PAT mix format lib/cuckoding/adapters/output_parser.ex test/cuckoding/adapters/output_parser_test.exs`:
  passed. After simplifying the decoder, formatting the parser alone passed.
- First `rtk env -u CR_PAT mix quality`: 370 tests and 10 properties passed
  (seed 480729); strict Credo then rejected nested decoder control flow.
  Replaced the nested branch with filtering through the same skip predicate.
  Final `rtk env -u CR_PAT mix quality` passed 370 tests and 10 properties
  (seed 313977), formatting, unused-lock check, warnings-as-errors compilation,
  strict Credo, Sobelow, and Hex audit. Expected fixture-crash logs are from
  supervisor recovery tests.
- `rtk env -u CR_PAT MIX_ENV=test mix run --no-start --no-compile /tmp/cuckoding-1052-replay.exs`:
  11 proposals passed the existing task validator including source confinement;
  97 public activity events and 1 usage record parsed. Asserted that the Repo
  process was not started and verified the artifact SHA-256 stayed unchanged.
  No proposal or usage record was persisted. The temporary replay script calls
  `OutputParser.extract/2`, `BoardTaskIntake.validate_output/2`,
  `OutputParser.activity_events/2`, and `OutputParser.usage_events/2` directly.
- `rtk git diff --check`: passed.

All commands use RTK. No dependency, migration, permission expansion, provider
invocation, or task import was added. The diagnostic envelope is a discard rule,
not an authentication mechanism; discarded text cannot authorize any action.
Actual normalized usage remains provider-reported, not a measured cost.

## Local integration and restart

The standing user request to merge into main and restart the app applies to
this follow-up fix. Applied menubar-shell and local-runner guidance. A fresh
read-only inventory found two blocked runs, one done run, one queued run, no
board execution, and no active agent session or stage attempt. The queued run
is preserved; no manual dispatch is requested. The currently running developer
bundle has shell PID 75985, BEAM PID 76059, and healthy listener 127.0.0.1:62527.
Process inspection used executable/PID/start identity only. A first Ruby
inspection using `require_relative` from `-e` failed without side effects;
loading the helper by absolute path succeeded. Ruby reports the pre-existing
world-writable DBngin PATH warning; no system permissions were changed.

- `rtk git commit -m 'fix(adapters): tolerate interleaved Codex diagnostics'`
  created `77aa2a4`; `rtk git switch main` and
  `rtk git merge --ff-only fix/1052-codex-diagnostic-output` integrated the fix
  without conflicts. No remote push.
- Gracefully stopped the old shell using the existing `DeveloperRestart`
  identity/descendant/wait helpers via
  `rtk env -u GEM_HOME -u GEM_PATH /usr/bin/ruby -e ...`. The guarded TERM was
  sent only to shell 75985 after matching its absolute bundle executable and
  start identity. All three descendants, including the prior defunct child,
  exited. No force kill or unrelated application shutdown.
- A read-only SQLite source connection and standard-library `backup` created
  the mode-0600 backup
  `~/Library/Application Support/com.cuckoding.desktop/manual-backups/1052-20260927T043848Z/cuckoding.sqlite3`.
  Integrity/FKs passed; SHA-256
  `aaaecb8b0ff78b4ca808611b9cd866e56bd0daf676831a42ff7073fd3a5a44e7`.
- `rtk env -u CR_PAT ./bin/dev.build`: passed from clean main at `77aa2a4`.
  Assets, warnings-as-errors production compilation, release assembly, metadata
  (6 tests/15 assertions), restart helper (6 tests/98 assertions), release
  promotion, Rust formatting/10 tests/Clippy and Tauri bundling all passed.
  The sterile verifier passed authentication/token replay, browser handoff,
  diagnostics redaction, graceful cleanup, crash-before/after-READY, safe mode,
  and update snapshot/migration/rollback checks. Its database is disposable;
  the user's database required no migration. Existing build/restart helper
  `rtk proxy` calls preserve exact subprocess/stream semantics.
- `rtk ./bin/dev.restart`: passed. A fresh inventory found exactly one owned
  shell, PID 44078 (2026-09-26 23:40:25 local), and bundled BEAM PID 44186
  (23:40:26), healthy at `127.0.0.1:52623`, plus its child setup process.
  The chosen bundle is
  `desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`.
- `rtk python3 /tmp/cuckoding-1052-data-check.py`: integrity/FKs passed;
  complete rows matched the backup for 2 projects, 2 boards, 16 tasks, 4 runs,
  7 sessions, 7 stage attempts, 8 prior proposals, and 22 migration records.
  The reported planning run remains blocked. No tasks were imported or run.
- The bundled `Elixir.Cuckoding.Adapters.OutputParser.beam` matches the new
  production release byte-for-byte, SHA-256
  `a60ec627d13d21790576894fc5799b95e6b3bec68f6ac0657c284c53b2c021cf`.
  Shell SHA-256 remains
  `5d6c951270e7566f7c363b2c9488d431f6ce5102ac91011f73c832707828987e`;
  the fix is in the bundled Elixir module. Closing task/worklog edits do not
  change the tested source build.

## Handoff and limits

Completed the parser fix, local integration and developer-app restart. Open
the authenticated dashboard through the menubar action and create a new
planning run to use the fix; old failures are not silently rewritten. Original
artifact replay is real captured-output evidence, not a new paid provider run.
No new real-provider execution, authenticated visual acceptance, physical
sleep/wake drill, signed clean-Mac release, or remote publication is claimed.
