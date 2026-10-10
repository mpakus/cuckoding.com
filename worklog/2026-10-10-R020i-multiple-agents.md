# R020i · Multiple saved agents

Claimed on clean main d0081bf; branch feature/R020i-multiple-agents.
Scope/acceptance: tasks/R020i-multiple-agents.md. No external publication.

The singleton Workspace owns the existing Codex profile. Add independent named
records without moving its profile or rewriting immutable Team/command history.
Reach: Foundation command/projection ownership, Storage, Dispatcher, Team,
Planning, Battle preview, Settings/Team UI, migration guards, fixtures and docs.

RTK proxy is used for exact source reads, scripts, native JSON transport and build
scripts where filtering changes semantics. All repository shell commands use RTK.
Ponytail full, architecture, agent-adapter, LiveView, security-review and
quality-gates apply. No new dependency or agent delegation.

Cursor assessment: installed 2026.09.15-d2fe57e; official CLI reference/config and
authentication docs plus installed --help were inspected. Empty private HOME,
CURSOR_CONFIG_DIR and AGENT_CLI_CREDENTIAL_STORE=file return signed-out JSON from
status --format json. models requires authorization. Fixed login supports
NO_OPEN_BROWSER. Installed script/index/chunks inspected for interface evidence
only; no provider code copied or bundled. Browser login uses cursor.com/loginDeepControl.
Official references: https://cursor.com/docs/cli/reference/parameters and
https://cursor.com/docs/cli/reference/configuration and
https://cursor.com/docs/cli/reference/authentication .

Native assessment caught Cursor creating a `latest.log` symlink on first launch,
which made the next strict profile inspection refuse it. Installed index.js:2
(logger module) exposes CURSOR_AGENT_DISABLE_DEBUG_LOG; set it to 1 and keep the
no-symlink rule unchanged. Early isolated QA profiles were retained, not repaired
by deleting unknown entries. No existing user Cursor profile was touched.

The named-connection decision was written before implementation and consolidated
into docs/DECISIONS.md D021 with the existing decision registry. No deferred
provider execution framework or new dependency was added.

## Result and validation

- Settings is a named-agent roster with Add/Edit and the existing four-step wizard.
  New connections own their profile, executable/status/catalog and saved selection.
  Team resolves each role against its chosen connection's saved models.
- Legacy `codex` keeps its profile and immutable histories. The ninth additive
  migration never rewrites prior data. Speculator planning freezes the exact named
  Codex connection; Cursor bindings report unavailable rather than falling back.
- Cursor setup supports the pinned fixed version/status/models/login/logout CLI.
  No inference, repository access or invented model IDs were added. Model IDs and
  labels come from the bounded complete catalog; unsupported effort/input fields
  are not fabricated. Setup remains globally serialized.
- `rtk mix quality`: 177 tests passed; format, warnings-as-errors compilation,
  Credo, Sobelow and dependency audit passed. Sobelow's existing Elixir 1.20
  quoted-keyword warnings while reading Mix.lock remain; no vulnerabilities found.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`: 48 tests
  passed. After adding debug-log suppression,
  `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked cursor::tests`:
  4 focused tests passed. The login/cancel fixture timeout was raised to two seconds
  after an under-load timing failure; no product deadline changed.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`: passed.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`: passed.
- `rtk proxy bin/dev.build`: passed, including the final Foundation provider guard.
  Packaging re-signs bundled dylibs after relocation; install_name_tool warnings
  about the replaced signatures are expected.
- `rtk proxy bin/smoke`: final pass in `/private/tmp/ccoding-smoke.7tsN8k`.
  Bundled launch/bootstrap/browser cookie, replay/origin refusal, heartbeat, graceful
  quit and listener cleanup passed.
- `rtk git diff --check`: passed. Changed-document local links were checked with
  `rtk proxy python3` (relative Markdown targets resolved against their files).

Migration evidence: SQLite backup API captured the running eight-migration DB as
`before-multiple-agents.db` under the proof root below. Integrity/foreign keys were
checked, then `rtk proxy env MIX_ENV=test mix run --no-start -e ...` started only
Ecto/Repo on `migration-copy.db` and ran `Ecto.Migrator.run(..., :up, all: true)`.
`rtk proxy python3` compared ordered-row SHA-256 fingerprints: all eleven prior
data tables were unchanged, ninth migration present, new table empty, integrity
and foreign keys valid. `before-records.json` retains counts and fingerprints.
No production data was reset or overwritten.

Actual provider evidence: the packaged native helper ran installed Cursor
`2026.09.15-d2fe57e` in a fresh private profile. Version passed (442 ms); two
signed-out inspections passed (330/329 ms), proving repeat use no longer fails
from the logger symlink. Login returned a validated Cursor URL; immediate Cancel
returned cancelled (384 ms). All observed child PIDs exited. URLs/account identifiers
were not printed or stored. `cursor-native-final.json` retains public receipts in
the proof root. Real signed-in Cursor catalog, completed login/logout and Grok
entitlement remain unverified; fixture models only prove selection/routing logic.

Installed reference evidence is pinned to `2026.09.15-d2fe57e` under
`~/.local/share/cursor-agent/versions/`: `index.js:2` (profile/logging environment),
`2062.index.js:2` (model output), `3442.index.js:2` (status), and
`3431.index.js:2` (login URL/NO_OPEN_BROWSER). Inspected interface snippets only;
no runtime source was copied and no runtime is bundled. Official docs were read
on 2026-10-10; their URLs appear above.

## Running artifact and browser evidence

Proof root: `/private/tmp/cuckoding-r020i-proof-m6ccdh4r`. Copied final development bundle: `/private/tmp/cuckoding-r020i-proof-m6ccdh4r/Cuckoding.app`.
Native SHA-256: `e945ea1e22e50ec3264def243461d44cfac66515cfb68a549579595d2d88b3a5`.
Shell PID 33721 (Sat Oct 10 13:22:59 2026);
BEAM PID 33738 (Sat Oct 10 13:23:00 2026); loopback port 55720.
Data: `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data`.

`rtk proxy python3 /private/tmp/cuckoding-r020h-proof-blc3dhoa/stop.py` verified
executable/parent/start identities, gracefully stopped only the old owned service,
and confirmed shell/listener cleanup. `rtk proxy python3
/private/tmp/cuckoding-r020i-proof-m6ccdh4r/launch.py` launched the new native shell
with its normal handshake against existing data. Integrity/foreign-key checks and
nine migrations passed; the legacy private ChatGPT status and ten-model catalog
were retained. Existing test launchers now point to this copy with the same data.

Native Chrome visibly rendered the authenticated dashboard and `/settings` roster,
showing legacy Codex signed in, its saved model selection and fresh catalog.
The user's active Chrome interactions then changed windows; further native UI
actions were stopped. A separate in-app preview was attempted but navigation was
blocked by the client. No screenshot or full interactive wizard pass is claimed.
LiveView regressions cover roster → Add Cursor → version → model selection → Save,
mixed Team pickers, changing-agent model reset, stale forms and scoped login/cancel.

Remaining acceptance: human-completed Cursor login and actual model catalog, Cursor
inference grants/planning, Claude/Hermes adapters, full interactive/narrow rendering,
clean-machine notarization and physical sleep/wake. No provider usage was incurred
by this slice and no personal Cursor/Codex configuration was adopted.

Local integration: commit this R020i slice and fast-forward merge into local main;
delete the merged task branch. No remote push, PR or deployment is authorized.
