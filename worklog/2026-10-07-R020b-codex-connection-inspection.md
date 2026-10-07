# R020b — Private Codex connection inspection

Claimed from clean local main `e6bf40b`. Acceptance: [task](../tasks/R020b-codex-connection-inspection.md).
Ponytail full, agent-adapter, local-runner, security-review, LiveView, quality-gates
and official OpenAI documentation applied. No subagents or new dependencies.
RTK proxy exceptions: exact source/schema reads, provider protocol, build and
subprocess verification must retain their output semantics.

Reuse the existing durable command/dispatcher and native owned-group cleanup.
Only initialize/initialized, config/read, account/read and model/list are permitted in this helper; no
general JSON-RPC proxy or task execution. Current installed schema: Codex 0.146.0.
Sources: [app-server](https://learn.chatgpt.com/docs/app-server) initialization,
account/read and model/list; [credential storage](https://learn.chatgpt.com/docs/auth).
No upstream implementation is copied; Codex rust-v0.146.0 is Apache-2.0 (R020a
license check). Human sign-in and actual inference remain separate acceptance.

## Delivered

Reused `lib/cuckoding/foundation.ex:94` command idempotency, claim/finish revision
checks and append-before-broadcast events; reused the owned child group and
private directory checks in `desktop/src-tauri/src/probe.rs:14`. The native
inspection is a fixed operation, never a general RPC proxy. Account observations
and validated model metadata have separate durable timestamps. Failed discovery
retains stale entries; 24-hour expiry is derived on display. Login, logout,
account switching and agent turns remain outside this slice.

Reference: installed 0.146.0 generated schemas under
`/private/tmp/ccoding-codex-schema-0146`, v2 GetAccountResponse/ModelListResponse/
ModelListParams and v1 InitializeResponse, checked against the official docs
above. File credential storage and effective OpenAI provider are verified after
initialization. No provider implementation or new dependency was copied.

## Checks and corrections

- `rtk mix format`; `rtk mix quality`: **38 passed**, formatting and compiler with
  warnings as errors, Credo, Sobelow and dependency audit passed. Initial Credo
  complexity findings were fixed by splitting field validation. Sobelow still
  emits its documented Elixir 1.20 quoted-keyword parser diagnostics.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`: pass.
- `rtk proxy cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`: pass.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`: **14 passed**.
  Covers private environment, account-field canaries, pagination, unsafe profile,
  effective-config mismatch, repeated cursor/IDs, malformed and oversized frames,
  server requests, timeout, cancellation, descendants and unrelated peer survival.
  A prior run exposed the shell lock held briefly by an inherited descriptor
  after concurrent fork. Explicit unlock on the owning guard's drop fixes this;
  a duplicated-descriptor regression makes that case deterministic.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/ccoding-r016-target bin/dev.build`:
  pass on final source. The alternate target avoids replacing the older running
  bundle. This historical target directory name does not identify the new build.
- `rtk proxy python3 bin/check-site`: **33 links/assets** and structure/scope pass.
- `rtk proxy node --test test/site_test.mjs`: **4 passed**. Only public readiness
  copy changes in this step; artwork/browser evidence is in R017.

The final native executable SHA-256 is
`db6fa47f213542cbfed57a1227cc83a8d427e5492e50b9696d9ad39ad661c508`, at
`/private/tmp/ccoding-r016-target/release/bundle/macos/Cuckoding.app/Contents/MacOS/ccoding`.

## Packaged and migration evidence

Invoked that executable with `--smoke-test` through `rtk proxy python3 -`, setting
`CCODING_RELEASE_DIR` to its `Contents/Resources/release` and `CCODING_DATA_DIR`
to each isolated directory below. Both passed native bootstrap, authenticated
browser cookie, replay/origin refusal, heartbeat, graceful shell Quit and closed
listener checks:

- Fresh: `/private/tmp/cuckoding-r020b-fresh-ellmrl3_`.
- Upgrade: `/private/tmp/cuckoding-r020b-upgrade-3ie47n2s`.

The upgrade input was a Python SQLite online backup of the stopped R017 smoke DB,
`/private/tmp/cuckoding-r017-smoke-20261007/foundation.db`, opened read-only.
Assertions verified migration count 2→3, unchanged original workspace columns,
all previous events/commands, new empty connection, integrity and foreign keys,
plus an unchanged SHA-256 of the source DB. An initial verification script used
the wrong plural `workspaces` table name; corrected to the actual singular schema
before the successful run. No user/live database was migrated.

## Real runtime and browser

`rtk proxy python3 -` launched the final native helper with
`--inspect-codex /Users/mpak/.local/bin/codex /private/tmp/cuckoding-r020b-real-final-q32c7sbb`,
kept helper stdin open until its result, discarded stderr, and asserted public
JSON plus absence of auth.json. Installed Codex 0.146.0 returned checked /
not_connected / not_requested in **366 ms**. Codex manages its own runtime cache
files in that private profile; Cuckoding never reads credential values.

The packaged GUI was then launched with isolated data
`/private/tmp/cuckoding-r020b-ui-qsbdt1pe`. CUA verified default-browser handoff,
metadata discovery, explicit version consent, explicit connection consent,
pending controls, the real signed-out result (**171 ms**), and persistence after
reload. SQLite contained exactly one completed attempt for each discovery,
version and connection command; connection pending/started/completed events
were retained. Native shell PID 39894 owned release PID 39895 on IPv4 loopback
60612 during this check. Screenshot:
`/Users/mpak/.codex/visualizations/2026/10/07/01a11422-7a5a-7251-87cb-1d8f8b8e5fd4/cuckoding-connection-desktop.png`.

An owned-release SIGTERM fault drill stopped this isolated instance. Its initial
ten-second cleanup observation expired; follow-up PID and listener checks proved
both owned processes gone and port 60612 closed. This does not establish a bounded
crash-recovery SLA. Graceful Quit was verified separately by both packaged smoke
runs. The temporary browser tab was closed; its data was retained. No unrelated
provider app or older Cuckoding instance was stopped.

## Scope and integration

Connected catalogs are fixture evidence only. Actual login/logout, model
entitlement, two-workspace scoped turns, physical sleep, clean-machine install,
signing/notarization and long-run recovery remain open. No API key requested,
personal auth imported, remote push or Pages deployment performed. README,
AGENTS and affected docs reflect these limits. Final link/path checks and
`rtk git diff --check` pass. Commit this R020b step and fast-forward local main;
R020 remains partial with login/logout and real provider execution next.
