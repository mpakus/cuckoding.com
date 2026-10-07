# R040e — Speculator proposals from a brief

Claimed on clean local main `ecd0de0`; owner Codex. Acceptance is in
[the task](../tasks/R040e-brief-planning.md). No remote publication authorized.

## Approach and references

Ponytail full, adapter, LiveView, workflow, local-runner, security-review and
quality-gates skills applied. Reuse the command ledger, private-profile lock,
restricted model-check transport, frozen team and revisioned draft writer. No new
dependency, worker, execution policy or migration.

Inspected existing `lib/cuckoding/codex.ex:104`, `foundation.ex:209`,
`tabulae.ex:66` and `desktop/src-tauri/src/connection/model_check.rs:108`.
Codex 0.146.0's generated `v2/TurnStartParams.json:111` describes `outputSchema`;
[official app-server documentation](https://learn.chatgpt.com/docs/app-server)
confirms it is a per-turn JSON Schema constraint. Reuse the existing protocol
implementation; no external implementation copied. Installed schema is interface
evidence, not proof of a successful real-account planning turn.

RTK proxy exceptions: exact source/schema reads, deterministic edit/QA scripts,
Mix and native build tools where filtering changes output or command semantics.
All repository shell invocations remain RTK-prefixed.

## Verification

Implemented and verified; local main integration is the final bookkeeping step.

- `rtk mix test test/cuckoding/planning_test.exs test/cuckoding_web/planning_live_test.exs test/cuckoding/model_check_test.exs`:
  14 passed initially. Consent/snapshot drift, idempotency, foreign scope, duplicate
  imports, malformed/oversized proposals, cancellation, lease interruption,
  durable reload and preserved manual drafts are covered.
- `rtk mix quality`: final 107 tests passed; formatter, warnings-as-errors compile,
  strict Credo, Sobelow and dependency audit passed. Sobelow emits the existing
  quoted-keyword warnings while reading Mix's generated lockfile; no findings.
- `rtk proxy cargo fmt --manifest-path desktop/src-tauri/Cargo.toml -- --check`: passed.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r040e-target cargo test --manifest-path desktop/src-tauri/Cargo.toml connection::model_check`:
  4 passed; early completion, structured contract, tool/foreign/model/grant refusal,
  cancellation, timeout and private-profile cleanup.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r040e-target cargo test --manifest-path desktop/src-tauri/Cargo.toml`:
  final 32 passed, including owned-group/parent-loss/peer preservation and Git regressions.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r040e-target cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --all-targets -- -D warnings`:
  passed, no warnings.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r040e-target bin/dev.build`:
  passed; rebuilt after the active-request history fix. Existing OpenSSL relocation
  invalidates then replaces ad-hoc signatures as designed. No dependency changes.
- `rtk proxy python3 /private/tmp/cuckoding-r040e-proof-7ie_qelj/verify-package.py`:
  fresh and prior-copy bundle smoke passed; six migrations, integrity `ok`, no FK
  violations, prior team/Arena/Tabula/draft/history rows preserved and source DB
  hash unchanged. Source was an isolated R040d fixture, not a live user database.
- `rtk proxy python3 /private/tmp/cuckoding-r040e-proof-7ie_qelj/start-browser.py`
  and `connect-browser.py`: seed an explicitly synthetic profile/model/team and
  Arena, launch only the isolated bundle, identify its child/listener without
  reading raw process arguments/environment, and authenticate the QA browser.
- CUA browser: missing-consent rejection; native fixture turn to two structured
  proposals; import exactly one into Specs; preserve unrelated unsaved manual
  text and the brief; cancel a second running turn and reject its late result;
  reload and restart with results/import status retained. At 390×844 the document
  and scroll widths both equal 390, with usable labels and controls. Temporary
  viewport reset and QA tab closed.
- `rtk proxy python3 /private/tmp/cuckoding-r040e-proof-7ie_qelj/unsigned-check.py`:
  real installed Codex `0.146.0` version observed, planning reports `not_connected`
  in a new private profile before inference. No personal profile/credentials used.
- `rtk proxy python3 /private/tmp/cuckoding-r040e-proof-7ie_qelj/restart-browser.py`,
  `connect-browser.py` and `verify-final.py`: final bundle retains exact command,
  task and revision rows and all prior events; only expected shell/browser auth
  events are appended. No command replay, no project changes, integrity/FKs pass,
  both fixture provider children exited and only the owned QA shell/BEAM stopped.
- Local Markdown-path script: 77 links resolved. `rtk git diff --check`: passed.

Review found that newer rejected requests could hide an active request behind the
five-row history limit. Active requests now sort first; regression coverage checks
that Cancel remains reachable. Final review also added a guarded fallback for
malformed component events; focused LiveView checks and the full quality gate
passed again before rebuilding and rechecking the final bundle. Initial compiler checks caught a call-site edit and
missing local LiveComponent wrapper; both were fixed before the green full gate.
The first version-probe harness closed stdin and correctly produced cancellation;
it was fixed to retain stdin ownership. Restart verification was corrected to
allow the expected new authorization events while requiring prior events intact.

## Artifact and scope

Final bundle: `/private/tmp/cuckoding-r040e-target/release/bundle/macos/Cuckoding.app`.
Native SHA-256: `dcdda9d1fe9154e8896ab306e8adc41612e0d27071911f20ea85b3dd15df4fd6`.
Planning BEAM SHA-256: `1c888318674a4ef950069655558324bb5063fa5118279c959727726d3ff48d2c`.
PlanningComponent BEAM SHA-256:
`298739a6e1b5ce29db3a9ec85594c66800d3889ba60bb98de3819809cd01e25f`.
Final QA shell/BEAM were `85375`/`85386`, loopback port `63433`; all stopped and
listener closed. Earlier fixture instances `81488`/`81493` on `62676` and `83930`/`83934` on
`63037` also stopped.
The existing user application/bundle and provider sessions were not replaced.

Screenshots: `/private/tmp/cuckoding-r040e-proposals.jpg` (final bundle after restart)
and `/private/tmp/cuckoding-r040e-narrow.jpg` (390-pixel fixture cancellation/form).
QA scripts, native receipts and identity files remain in
`/private/tmp/cuckoding-r040e-proof-7ie_qelj/`.

Successful planning is protocol-fixture evidence only. Human-completed login,
real-account successful planning, adversarial real-runtime grant enforcement,
file-backed specs/inputs, battle execution, physical sleep and signed clean-machine
release acceptance remain open. No public site deployment, push, PR or remote
merge was performed. This change completes R040e, not the full R040/R020 gates.

