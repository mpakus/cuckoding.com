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

Build, restart, final validation, and historical-state checks are pending.
