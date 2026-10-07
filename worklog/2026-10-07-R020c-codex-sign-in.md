# R020c — Private Codex sign-in and sign-out

Claimed clean main `4a82081`; acceptance in [R020c](../tasks/R020c-codex-sign-in.md).
Ponytail full 4.13.0 (MIT), agent-adapter, local-runner, security-review,
elixir-phoenix-liveview, quality-gates and OpenAI Docs applied. No subagents.
RTK proxy exceptions preserve exact source/protocol, Python checks and build output.

Reuse Foundation's durable command ledger, Codex normalizer and bounded native
RPC/group cleanup. Reference: Codex 0.146.0 generated schemas in
`/private/tmp/ccoding-codex-schema-0146/v2/LoginAccount{Params,Response}.json`,
AccountLoginCompletedNotification and CancelLoginAccountParams; no upstream
implementation copied. Existing Codex Apache-2.0 license evidence is in R020a.
Current official [app-server](https://learn.chatgpt.com/docs/app-server) and
[authentication](https://learn.chatgpt.com/docs/auth) docs checked this turn.

Acceptance: explicit private-profile login/logout, transient validated official
URL, matching completion and model refresh, bounded cancellation/cleanup,
durable uncertainty with no auto-replay, reconnectable UI and honest real-account
evidence. Implemented and verified; integration is the final local-main operation.

## Result

- Reused the durable command ledger and fixed native app-server helper. Added
  separately consented `login_codex` / `logout_codex`, stable command keys,
  account/catalog invalidation before launch, native exclusive profile locking,
  matching managed ChatGPT completion and fresh account/model observation.
- Login is bounded to ten minutes by monotonic and wall-clock deadlines; RPCs
  remain ten seconds. Cancel requests the provider cancellation, stops its owned
  group, and waits for helper exit. Late success cannot restore a cancelled
  account/catalog. Uncertain cleanup stays visible; interrupted auth never replays.
- The expiring official login URL lives only in dispatcher-owned ETS. LiveView
  gets a boolean and local command link; the session-protected redirect expires
  with the active operation. No URL/login ID/raw provider errors go into app
  state/events/logs. The provider owns its credential files; Cuckoding never reads
  or imports token contents. Existing connected profiles are observed, not replaced.
- LiveView exposes progress, elapsed time, reconnect, Cancel and confirmed private
  sign-out. Unknown timings are not displayed as zero; an empty invalidated catalog
  is not described as a saved stale catalog. No dependencies or migration added.

## Verification

Final commands and results:

| Command | Result |
| --- | --- |
| `rtk mix quality` | PASS: 45 ExUnit tests; formatter, warnings-as-errors compile, Credo, Sobelow and dependency audit |
| `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check` | PASS |
| `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings` | PASS |
| `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked` | PASS: 18 tests |
| `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r020c-target bin/dev.build` | PASS: final macOS bundle, isolated from older running artifacts |
| `rtk proxy python3 /private/tmp/cuckoding-r020c-acceptance.py` | PASS: installed Codex login start/cancel, inspect and logout in populated private profile; each owned provider leader stopped; final packaged smoke |
| `rtk proxy python3 bin/check-site` | PASS: 33 links/assets, public scope and structural/motion checks |
| `rtk proxy node --test test/site_test.mjs` | PASS: four tests; site changes only synchronize capability copy |
| `rtk git diff --check` | PASS |

Sobelow still emits its known Elixir 1.20 quoted-keyword diagnostics while parsing
Mix.lock; no findings. Packaging re-signs relocated crypto libraries as documented
in Development. Initial checks exposed an outdated sign-in copy assertion and
Credo nesting; both were corrected. A later UI assertion was scoped to the
connection result rather than unrelated existing version details.

Packaged testing found a real recovery defect: Codex's private bundled-plugin
cache contained 7,889 ordinary entries, exceeding the previous 4,096-entry metadata
limit. No socket/special file was present (correcting the initial hypothesis).
Raised the still-bounded limit to 32,768, retained all link/special-file refusals,
and added an 8,000-entry acceptance/oversize-refusal regression. Repeated real
start/cancel → inspect → logout then passed against that populated profile.

Additional `rtk proxy python3 -` checks used stdlib sqlite3/subprocess, with raw
provider/stderr data suppressed. A backup of the stopped prior R020b database
booted and passed packaged smoke at `/private/tmp/cuckoding-r020c-prior-onnfkceq`:
all schema versions unchanged, events retained, integrity/foreign keys valid,
source DB SHA-256 unchanged. No migration is introduced. Final fresh smoke data:
`/private/tmp/cuckoding-r020c-final-smoke-tpe0e9me`.

Desktop browser testing through CUA used the actual packaged app and installed
Codex 0.146.0: discovery/version, login prompt, browser reload preserving the same
local link, Cancel removing the link, private logout and connection recheck.
After the cache fix, final UI inspection returned signed out in 148 ms and private
logout returned signed out in 146 ms; final cancellation retained its measured
elapsed duration and unknown account state. No OpenAI page was opened, account
access granted or auth.json created. Application tables were checked for absence
of provider URLs/login IDs/token fields. Screenshots:
`/private/tmp/cuckoding-r020c-final-login.png` (final packaged login controls).

Final UI data: `/private/tmp/cuckoding-r020c-ui-sv8vqi2r`; shell PID 3142,
listener `127.0.0.1:59453` at test time. Only the identified test release was sent
SIGTERM afterward; shell/release/listener cleanup was checked and data retained.
This is failure-exit evidence; the separate packaged smoke exercises graceful
Quit. These PIDs/ports are historical, not current-running-build claims.

A stdlib relative-link check resolved README/AGENTS/docs/task file targets; public
claims distinguish implemented controls from real-account acceptance. No new UI
layout/CSS was introduced. Narrow app rendering and physical keyboard traversal
were not re-exercised here; LiveView checks cover labels, consent and reconnect.

## Integration and remaining gates

Commit this single R020c branch and fast-forward local main after verification.
README, AGENTS, current contracts, plan and site capability copy are synchronized.
No push, Pages deployment or public release is performed. The built preview is
`/private/tmp/cuckoding-r020c-target/release/bundle/macos/Cuckoding.app`.

R020 remains partial. Human-completed login, a real signed-in catalog and model
entitlement, revocation, isolated read/write turns in two workspaces, physical
sleep and forced-helper ownership recovery remain open. Fixtures prove matched
login completion and catalog refresh only. No roles, Arenas or battles execute.
