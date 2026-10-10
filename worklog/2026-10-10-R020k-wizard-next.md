# R020k · Explicit connection wizard Next

Claimed clean main c034e5e on fix/R020k-wizard-next.
Scope: HomeLive's shared Codex/Cursor wizard navigation, catalog-recovery UI and
LiveView tests. No provider protocol, credentials, database or execution changes.
The old step-2 button vanished unless the catalog was available, although account
connection and catalog refresh are separate observations. Preserve the latter's
freshness/save gates while allowing connected users to inspect/retry on step 3.
Ponytail full 5.1.0 (MIT), LiveView and quality-gates apply. Native restart uses
existing owned-instance identity/cleanup flow. RTK prefixes shell commands; proxy
preserves exact source, script, build and diagnostic output.

Observed the reported Cursor connection read-only: account checked/authorized,
catalog stale with `refresh_failed`, zero models. No credentials or raw provider
output were read. This explains why the old conditional button was absent.

Implemented persistent Back/Next footer on step 2. Next stays disabled before
verified connection/during setup, but connected stale catalogs may open step 3.
That step retains freshness gates and provides a scoped Refresh models form.
No navigation event launches a provider or changes durable state. Existing
inspection commands already own refresh receipts/events. Empty selections cannot
request Review. Existing selected models survive Back/Next and clock updates.

Verification:
- `rtk mix test test/cuckoding_web/agents_live_test.exs test/cuckoding_web/foundation_live_test.exs`:
  18 passed. Both Codex and Cursor cover visible disabled Next before sign-in,
  refused forged navigation, pending disabling, failed-catalog progression without
  a new command, disabled stale selection/review, rejected recovered refresh forms,
  successful scoped refresh, retained choices and review/save. Existing reconnect
  and expiring-session checks also pass.
- `rtk mix quality`: 181 passed; formatting, warnings-as-errors compile, Credo,
  Sobelow and audit passed. Existing Sobelow quoted-keyword lockfile warnings only.
- `rtk proxy bin/dev.build`: passed, normal relocation/re-sign diagnostics.
- `rtk proxy bin/smoke`: passed native handshake/session/routes/origin/replay,
  heartbeat, graceful shutdown and listener cleanup; retained `/private/tmp/ccoding-smoke.xhe2IU`.
- `rtk proxy git diff --check`: passed. Python validated 115 changed-document links.
- No pending/running/cancelling command existed before restart. Prior owned
  artifact stopped via its identity-checked graceful script, including shell and
  listener cleanup. New native handshake preserves the existing rebuild data at
  `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data`; retained test launchers updated.
- Packaged BEAM equals the assembled release; comparing to the unstripped compiler
  output first differed because the release strips debugging chunks.

Running artifact: `/private/tmp/cuckoding-r020k-proof-gcu9j6mp/Cuckoding.app`, loopback port 57890.
Shell PID 45359, BEAM 45373; verified recorded start identities.
Native SHA-256 `56a0063cbf72f40286de5d1ce03c91b2861f035e5a4d3f211375e8131ddaf7e0`. Bundled HomeLive BEAM matches
the assembled release file, SHA-256 `d16fff8502e7d51dcb5b6112ea1a4565e8181a9a3a1e054c9a854a8cb32b92c7`.

Manual app clicks were not verified: exact-path native tray inspection timed out;
LiveView and packaged tests supply this slice's evidence. Cursor's real model
fetch failure remains unresolved; this change exposes recovery and does not
invent a catalog or relax Save. No real provider refresh/inference was run.
Rust/provider/migration/sleep/clean-machine gates were not repeated for navigation.
Docs, README and AGENTS updated. Local main integration only; no push/deployment.
