# R020d — Bounded Codex model-access check

Claimed clean local main `d98fd09`. Acceptance: [R020d](../tasks/R020d-model-access-check.md).
RTK, Ponytail full 4.13.0 (MIT), adapter, runner, security-review, LiveView,
quality-gates and OpenAI Docs applied. No subagents. Exact source/schema/protocol,
build and Python checks use `rtk proxy` to avoid altering machine-readable output.

User-requested branch cleanup: all nine non-main local branches were ancestors
of main, including `save/old-v2`; `git log main..branch` had no outstanding work.
Deleted only these merged local references with `rtk git branch -d`. Remote
`rtk git ls-remote --heads origin` showed only main at `4a82081`; no remote branch
deletion or push was needed/performed. All committed work remains in local main.

Acceptance restated before implementation: one explicitly consented fixed model
check, fresh verified model/account/executable, private restricted runtime setup,
matching completion, bounded cancellation/cleanup, durable public evidence and
reconnectable UI. It is not a repository task or proof of the complete R020 story.

References: existing Foundation/Dispatcher/Codex/profile helper and current
[official app-server documentation](https://learn.chatgpt.com/docs/app-server).
Installed Codex 0.146.0 generated stable and experimental JSON schemas. Inspect
actual supported fields rather than trusting newer web examples. No credentials
read/imported and no API-key integration introduced.


## Implementation and source evidence

Reused the command ledger, exclusive profile lock, bounded RPC transport,
private storage and cleanup-aware helper collector. Added no dependencies,
migrations, general RPC bridge or repository runner. The feature uses a fresh
catalog/connection identity snapshot and least advertised effort, fixed prompt,
verified named permissions, exact public completion and a closed durable receipt.

Sources: Codex tag `rust-v0.146.0`, Apache-2.0 verified from its LICENSE;
`codex-rs/core/config.schema.json:2472` (filesystem), `:4915` (default_permissions)
and `:5570` (profiles). Local generated experimental schemas:
`v2/ThreadStartParams.json:76,127,144` and `v2/ThreadStartResponse.json:16,64,74`.
Adapted the named-profile/thread binding contract, not upstream implementation
code. Current web examples include fields missing from installed 0.146.0; the
installed schema and runtime response determine acceptance.
[Official permission docs](https://learn.chatgpt.com/docs/permissions) and
[app-server docs](https://learn.chatgpt.com/docs/app-server) were cross-checked.
Cuckoding additionally fixes the prompt, denies tools/permission expansion,
checks intent/model/completion and discards raw/hidden content before persistence.

## Verification

- `rtk proxy /Users/mpak/.local/bin/codex app-server generate-json-schema --experimental --out /private/tmp/cuckoding-codex-schema-0146-full`: passed.
- `rtk mix format`; `rtk mix quality`: passed, **53 tests**, compiler warnings-as-errors,
  Credo clean, Sobelow scan and dependency audit clean. Known Sobelow/Elixir 1.20
  generated-lockfile quoted-keyword warnings remain tool diagnostics.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`: passed.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`: passed.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`: **21 passed**.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/cuckoding-r020d-target bin/dev.build`:
  passed; isolated bundle at `/private/tmp/cuckoding-r020d-target/release/bundle/macos/Cuckoding.app`.
  Existing Tailwind signing/OpenSSL relocation warnings handled by the build script.
- `rtk proxy python3` isolated native-helper/RPC checks: real 0.146.0 effective
  configuration accepted; signed-out helper returned `not_connected` before
  inference (debug root `/private/tmp/cuckoding-r020d-unsigned-q4slhv3m`, packaged
  root `/private/tmp/cuckoding-r020d-packaged-unsigned-gsf5spxy`). No auth imported.
- Real no-turn `thread/start` preflight in
  `/private/tmp/cuckoding-r020d-thread-jg7d05q2` confirmed requested/runtime model,
  profile ID, read-only/network-disabled grant, empty instruction sources and
  ephemeral thread with no persisted path. It returned empty workspace roots
  for an exact-path profile; narrower empty roots are accepted, wider roots refused.
- Packaged `--smoke-test` via `rtk proxy python3` with explicit bundle/data env:
  fresh root `/private/tmp/cuckoding-r020d-fresh-pbu2bold` and prior-schema copy
  `/private/tmp/cuckoding-r020d-prior-copy-56hbdl5e` passed launch, bootstrap,
  cookie/handoff, replay/origin refusal, heartbeat, graceful Quit and listener cleanup.
  Both retain 3 migrations; SQLite integrity/foreign keys passed. Prior workspace,
  commands and every historical event survived; new lifecycle events append.
  Source DB `/private/tmp/cuckoding-r020c-final-smoke-tpe0e9me/foundation.db` hash unchanged.
- CUA/default-browser packaged fixture at `/private/tmp/cuckoding-r020d-browser-ajz1o2ia`:
  version verification, catalog, model selection, keyboard submission, running
  progress, passing receipt/reload and cancellation passed. Models explicitly
  say “Fixture … (no provider)”. The native helper and actual SQLite ledger were used;
  this is not a real account or model-response test. Saved pass records matching
  requested/runtime model-a, thread/turn UUIDs and measured 2130 ms; model-b cancelled.
- Owned release-stop drill: verified release PID 16806 parent 16805 and exact
  isolated bundle path; SIGTERM to that release made its shell exit and port 62529
  close, preserving data. This is separate from smoke's graceful Quit evidence.
- `rtk proxy python3` Markdown-reference validation: **83 local path references**
  across 22 current contract/task files passed. `rtk git diff --check`: passed.

Failures found and corrected: current config/read expands optional null fields,
which are now pruned before exact permission comparison; real exact-path profiles
return no workspace roots. A browser fixture omitted the digit-suffixed feature
`multi_agent_v2`, correctly causing preflight refusal; fixed only the fixture,
reverified its changed executable and refreshed the catalog. An initial old-copy
UI assertion, Credo arity/complexity findings and copy formatting check were fixed
before final green checks. A prior-copy assertion initially compared all events
for equality; corrected to require preservation plus legitimate appended events.
A stdin-closed helper probe correctly cancelled; rerun with its owner pipe open
produced the intended signed-out refusal. Python HTTPS local trust lookup failed;
verified TLS curl retrieved the pinned license/config; an obsolete spec.rs path
returned 404 and was not used.

## Remaining gates

Human-completed private-profile login, real signed-in model response, adversarial
real filesystem/tool enforcement, two-Arena read/write tasks, physical sleep and
clean-machine signed/notarized release remain open. No real inference prompt,
credential entry, remote push, Pages deployment or public release occurred.


Final copy corrections keep account status separate from completed model checks
and distinguish a shorter RPC timeout from the total two-minute ceiling.
`rtk mix quality` passed again after formatting those edits: 53 tests, clean
Credo/security/dependency checks with the same documented tool warnings.
Rebuilt the isolated bundle and reran packaged smoke in
`/private/tmp/cuckoding-r020d-final-smoke-nc1a2s2p`: passed.
Final native SHA-256: `b6a410918ef67d1474a2b3848bea8a275c2420ea5647c08337dcfe4a934de467`.
Reopened the same fixture workspace from that bundle (shell 19287, listener
63112); the final UI copy and cancelled result survived application restart,
without another model command. Screenshot:
`/private/tmp/cuckoding-r020d-model-check.png` (explicit fixture, no provider).
No new narrow-viewport or screen-reader run; keyboard/labels/reconnect are checked,
and broader responsive/accessibility acceptance remains R080.

Security/minimalism review traced browser consent to durable admission, exact
helper argv, private path/config, bounded untrusted output and normalized receipt.
No raw reasoning or provider account details reach app records. No dependency,
new table or general-purpose provider bridge was needed. Physical/real-provider
restrictions remain documented rather than inferred from fixtures.

Final test instances and their browser tabs are stopped/closed; fixture data is
retained. Final restart preserved exactly two completed diagnostic commands
(one refusal, one pass) and one cancelled command, with no replay. Port 63112
closed after the owned release-stop drill. The pre-consent-fix HomeLive BEAM SHA-256 was
`b6c6847bfe119761b406fcc50e8122bd5d49056ae482c5bae3b1b2302f727316`;
the later consent-reset safeguard is rebuilt and checked separately below.

Local integration: verification complete; awaiting commit and fast-forward into
main. Remote publication and the user's previously opened app are unchanged.

Final review added one narrow safeguard: a changed connection observation clears
model usage confirmation while preserving the selected model. The existing
LiveView regression now refreshes a confirmed connection and verifies that reset.
This prevents a refreshed/replaced account/catalog from inheriting a UI checkbox.

After the consent-reset fix: `rtk mix quality` passed (53 tests and static gates);
rebuilt using the same `CARGO_TARGET_DIR` command; packaged `--smoke-test` passed
in `/private/tmp/cuckoding-r020d-consent-smoke-mjhxcxp_`. Final HomeLive BEAM SHA-256:
`67f5ce269119a34c9d2ef49e45d75691e879961b3de2d411205ec86a2448bd40`. The last native UI screenshot remains visually representative;
the additional consent reset is verified by the runnable LiveView regression.

Final remote read (`rtk git ls-remote --heads origin`) still showed only main,
now at `d98fd09` rather than the initial `4a82081`: earlier work was published
outside this turn while implementation ran. This turn performs no push.
`rtk git fetch --prune origin` refreshes local tracking before final integration.
