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
