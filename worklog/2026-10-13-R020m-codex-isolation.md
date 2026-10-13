# R020m — Execution isolation conformance

## Scope and reference

Next prerequisite from PLAN: verify Codex's actual filesystem/network enforcement
before repository tools. Ponytail full, agent-adapter, local-runner,
security-review, architecture and quality-gates applied. Existing Agents/Team
and private authorization profiles remain intact; no model usage is required.

Official references inspected 2026-10-13:
[permissions](https://learn.chatgpt.com/docs/permissions) (named filesystem
profiles, minimal-system access, explicit temporary-root denial) and
[app-server](https://learn.chatgpt.com/docs/app-server) (effective thread policy).
Installed desktop Codex reports `0.162.0-alpha.17.2`; local `sandbox --help`
confirms `-P`, `-C` and literal argv after `--`. No upstream source was copied.

Initial disposable tests demonstrated that `:minimal` alone exposes the temporary
root. Explicit `:tmpdir`/`:slash_tmp` denial plus a narrower owned root allowed
owned writes while refusing sibling/profile/protected accesses. These are CLI
sandbox checks, not model-tool or battle acceptance.

All repository commands use RTK. `rtk proxy` preserves exact source, JSON,
generated schema and multiline scripts, where filtering would change meaning.
No credentials or personal provider profile were inspected.

## Verification

- `rtk mix test test/cuckoding/isolation_test.exs test/cuckoding_web/isolation_live_test.exs test/cuckoding_web/agents_live_test.exs test/cuckoding_web/foundation_live_test.exs`:
  29 passed. Consent, stale forms, expired sessions, per-connection scope, runtime
  changes, immutable events, interruption without replay and cleanup-held cancel.
- `rtk mix quality`: final run 205 passed; format/compile/Credo/Sobelow/audit exit 0.
  Initial Credo complexity/alias findings were fixed; generated Mix-lock parsing
  warnings remain. Hex build resolution separately reports the existing Decimal
  3.1.1 EEF-CVE-2026-97853 advisory, despite mix_audit reporting no findings.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`:
  final run 56 passed, one explicitly opt-in real-provider test ignored.
  Native checks cover unsupported/unsafe fixtures, permissive fake runtime,
  cancellation/timeout with dead owned groups, and delayed network control.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check` and
  `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`:
  passed. Initial unnecessary unwrap and a rejected 2024-edition syntax attempt
  were replaced with the project's supported 2021 match pattern.
- `rtk proxy env CUCKODING_TEST_CODEX=/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex CUCKODING_ISOLATION_CANARY=fixture cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked isolation::tests::real_codex_two_workspace_isolation -- --ignored`:
  passed separately against actual `0.162.0-alpha.17.2`, including inherited
  environment canary exclusion. No model usage or private-profile import.
- `rtk proxy bin/dev.build`: passed. `rtk proxy bin/smoke`: passed; final retained
  smoke root `/private/tmp/ccoding-smoke.E76sMg`.
- Local Markdown reference validation for 12 changed documents and
  `rtk git diff --check`: passed.

## Packaged verification and retained data

Owned original shell/BEAM start identities and listener were verified before
graceful shutdown. SQLite backup `/private/tmp/cuckoding-r020m-proof/before.db`
passed integrity/foreign-key checks; all eleven durable table hashes retained.
Saved workspace/data selection and ignored launcher are preserved.

A fresh isolated app root `/private/tmp/cuckoding-r020m-proof/qa/data` was opened
through the normal native bootstrap. Browser actions added a named Codex,
performed its actual version probe and ran the optional check without sign-in.
An initial network-control-stage failure returned no pass; a new consented check
succeeded. The exact transient cause was not proven. Nonblocking accept was then
made cancellation/deadline-aware and covered by a delayed-connect regression;
network-setup failures now have a distinct normalized status. Final rebuilt
browser check passed in 881 ms with five child identities. The earlier pass
survived a packaged restart without replay. The four wizard steps and dated result
were inspected in the desktop browser. QA was stopped with verified cleanup.
Public receipts and launch/stop identity proofs are retained under the proof root.
The current bundle was relaunched with the saved user data root at
`http://127.0.0.1:51697/`. All eleven durable tables match the consistent
pre-build backup exactly; integrity and foreign-key checks pass. Browser session
rows/events are expected to change on launch. Local main integration follows
verification; nothing is pushed or published.

No migration, dependency, account access, model inference, Arena access or new
mandatory setup step. Narrow viewport, real model tools, revoked-account,
physical sleep/wake and clean-machine release acceptance were not performed.

## Next execution gate

This closes only the fixed CLI-sandbox prerequisite. Next implement and verify
the actual app-server task turn with effective config/thread permission checks,
bounded public tool events, protected project policy, cancellation and independent
sessions. It must reuse the exact named connection/model and owned checkout; a
sandbox receipt is never a grant. Then implement R050d/e's durable single Start
and independent review loop. Do not add another mandatory diagnostic wizard.
