# R020o — Codex task-tool routing

Ponytail full, agent-adapter, local-runner, security-review and quality-gates apply.
All shell commands use RTK; proxy preserves exact source, protocol and fixture
output. The baseline main is 48c9e04; no unrelated dirty edits.

Acceptance: restore task tool routing without broad host access, keep no-tools
diagnostics/planning unchanged, and run only the remaining authorized write turn.
The first approved read turn already consumed usage and failed before tool calls.

Reference inspection (no source copied): OpenAI Codex, Apache-2.0, revision
`cf0ed4c600161fcaa18eeac02b5fc715e1076955`, retained outside the repo at
`/private/tmp/cuckoding-codex-code-mode-xpvjkf8h`.
`codex-rs/code-mode/src/remote_session.rs:86-95` explains the disabled-host error;
`codex-rs/code-mode-runtime/src/runtime/globals.rs:15-51` supplies only pure
helpers and enabled tool callbacks; `codex-rs/code-mode-runtime/src/runtime/module_loader.rs:201-213` rejects
all imports. This supports task-only Code Mode routing, not Node or arbitrary
host execution. Cuckoding still authorizes only its three descriptor-relative
file tools, verifies effective config and retains process-group cleanup.

The installed 0.162.0-alpha.17.2 app-server JSON schema requires `type: function`
for dynamic functions and accepts explicit `deferLoading: false`. Official
app-server documentation describes the item/tool/call exchange:
https://learn.chatgpt.com/docs/app-server#dynamic-tool-calls-experimental

Python's default TLS trust store failed to validate GitHub; switched to system
curl with normal certificate verification. No TLS checks bypassed.


## Real acceptance

The remaining approved write turn used the exact c2 profile and GPT-6.1 Sol.
In 9.2 seconds it called read_file successfully and verified the expected source
hash. It then returned blocked: runtime read-only instructions were interpreted
as forbidding the separately authorized host edit tool. No edit was attempted;
source.txt remained unchanged. Receipt:
`/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data/probes/00000000-0000-4000-88de-2a125d180020-task-acceptance/receipt.json`.
No new Codex/Code Mode host process remained in the executable-only process
comparison after return. The first read and this write turn exhaust the user's
two-turn consent. Requested one additional five-minute synthetic write turn after
clarifying the host-service grant; do not run until the user authorizes it.

The third-party dynamic handler forwards calls to the client independently of
local sandbox permissions (`codex-rs/core/src/tools/handlers/dynamic.rs:118-170`).
Clarified per-role developer instructions instead of broadening runtime roots.
Read-only roles retain no edit tool or authority. This is the same host capability
grant, not a new runtime filesystem permission or a prompt-based enforcement gate.
Host validation remains authoritative regardless of model interpretation.

Lifecycle caveat: upstream `codex-rs/code-mode/src/remote_session/connection.rs:157-169`
starts its own process group. `codex-rs/code-mode-host/src/lib.rs:148-184` handles EOF and
bounded session shutdown. Normal cleanup was observed; do not infer real crash,
sleep or mid-call cancellation acceptance from that observation.


## Verification

- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`:
  62 passed, 2 consented real-provider tests ignored. Includes successful read/write
  fixture callbacks, read-only edit rejection, disabled routing/effective-policy
  rejection, and no-tools diagnostics/planning rejecting task routing flags.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`: passed.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`: passed.
- `rtk git diff --check`: passed.
- No Elixir, database schema or frontend changes in R020o; R050d1's 208-test
  `rtk mix quality` result applies to those unchanged sources, not a new run.
- Before rebuild, saved workspace backed up at
  `/private/tmp/cuckoding-r020o-proof-5r0s6u6v/before.db`; exact owned process/start
  identities checked and no pending/running/cancelling commands present.
  Initial read-only ledger query used nonexistent status; corrected to schema's
  state column. No writes were made by that failed query.

- `rtk proxy bin/dev.build`: passed, prod compile and native app bundle built.
  Expected OpenSSL relocation/ad-hoc signing warnings; no release certification
  inferred. All three generated release directories contain only Decimal 3.2.0.
- `rtk proxy bin/smoke`: passed bundled launch/session/origin/bootstrap/heartbeat
  and graceful cleanup. Evidence: `/private/tmp/ccoding-smoke.z1TkuC`.
- Relaunched the exact saved test data root with the unchanged saved launcher.
  Observed shell 32513, BEAM 32515, loopback 55147; binary hash/start identities in
  `/private/tmp/cuckoding-r020o-proof-5r0s6u6v/proof.json`. All 11 durable tables
  match the pre-rebuild backup. These are dated observations, not future PID claims.
- Checked changed Markdown relative links and source/diff boundaries.

## Handoff

Routing fix and synthetic regression coverage are complete; real write acceptance
is pending the additional usage approval. The host grant wording changed after
the last real turn and has only fixture validation. Do not present Start as
implemented: durable admission/attempts, stage dispatch, project checks,
independent review/integration, recovery, parallelism, remaining providers and
release gates remain open. No remote push/deployment or Arena run occurred.

## Approved write follow-up

User explicitly authorized one additional synthetic write turn on 2026-10-13.
Reusing the existing fixture without product code changes. Ponytail full 5.2.0
(MIT) and quality-gates apply; RTK proxy keeps exact test and receipt evidence.
Acceptance: exact c2 connection and GPT-6.1 Sol, fresh private fixture, maximum
300-second runtime, host read then hash-guarded edit, exact final bytes and normal
process cleanup. This does not run an Arena or authorize further inference.


Result: PASS. Exactly one additional inference turn ran; no retry or extra model
call was made. The same existing native test ran with these explicit selectors:

```sh
rtk proxy env \
  CUCKODING_TEST_CODEX=/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex \
  CUCKODING_TEST_PROFILE=/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data/agents/a51c73cb-197d-4708-ae1f-1a9bbd1f3657 \
  CUCKODING_TEST_MODEL=gpt-6.1-sol \
  CUCKODING_TEST_TASK_ACCESS=write \
  CUCKODING_ALLOW_MODEL_USAGE=one-fixture-turn \
  cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked \
  connection::task_turn::tests::real_codex_task_tools -- --ignored --nocapture
```

- One passed, zero failed; native elapsed 10,880 ms (limit 300,000 ms).
- Requested/observed model both `gpt-6.1-sol`; exact c2 profile, no fallback.
- Exactly read_file then edit_file, both completed. Verified the before hash,
  after hash and bytes `CC_FIXTURE_AFTER` followed by one newline. No extra files.
- Final SHA-256: `4dfeac24c0e7f710f8d7fe1498dd337b37c7e7c98a4b29afb4a26bed38308b06`.
- Native Codex PID 33895 and Code Mode host PID 33932 were observed with their
  executable, start identity, parent and process group during the test; all
  observed test descendants were gone afterward. No unrelated process was stopped.
- All 11 durable application tables matched the read-only pre-test SQLite backup.
  The running app was not restarted; no product code or generated artifact changed.
- Evidence root: `/private/tmp/cuckoding-r020o-write-dag93z_n` contains exact test
  output, selectors, baseline source commit, process identities and verification.
- Receipt: `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data/probes/00000000-0000-4000-88de-2a93608b0230-task-acceptance/receipt.json`.
- New synthetic checkout: `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data/runtime-home/worktrees/00000000-0000-4000-88de-2a93608b0230/checkout`.

This supersedes the pending-write handoff above. It verifies one normal synthetic
write turn only, not actual Git worktree creation, an independent reviewer,
crash/sleep recovery, other models/providers or the unfinished Start loop.
Documentation-only follow-up: changed-link checks and `rtk git diff --check` apply;
full compilation/unit suites and packaging were not repeated without source changes.
