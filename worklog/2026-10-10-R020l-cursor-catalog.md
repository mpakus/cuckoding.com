# R020l · Cursor model catalog

Claimed on clean main 2ae4b78; branch fix/R020l-cursor-catalog.
Acceptance: tasks/R020l-cursor-catalog.md. Reach: native Cursor catalog parser,
Elixir normalization if needed, fixtures, public catalog projection and wizard,
docs and packaged test app. Preserve credentials, stored profiles and choices.

Ponytail full, agent-adapter, security-review, local-runner and quality-gates apply.
RTK proxy is used for exact source reads, bounded diagnostic scripts and native
transport/build output where filtering changes semantics. No inference, invented
models, personal provider configuration, external publication or new dependencies.

Initial evidence: the selected private Cursor account is connected but the latest
catalog refresh failed; R020k only repaired wizard navigation around that failure.

## Root cause and change

A read-only `models` command using the selected installed Cursor CLI and its
existing private profile returned exit 0 and 12,734 stdout bytes: 256 advertised
entries, plain UTF-8, no ANSI. Inspection held the existing native flock, cleared
inherited environment, retained the fixed private profile/environment, bounded
stdout/deadline and cleaned only its owned process group. No raw account output,
credentials, inference or personal profile was used.

The native parser and Elixir normalizer each capped rows at 128. The complete
valid response therefore became refresh_failed/stale. Raise both caps to 512,
and raise saved selections to the same ceiling so the complete list can be saved.
Keep the 64 KiB command output limit, ID/name checks, footer/completeness and
duplicate checks unchanged. Existing selection receipts still validate against
the exact current connection/catalog, version identity and setup revision.

Local interface reference: installed Cursor 2026.09.15-d2fe57e
`~/.local/share/cursor-agent/versions/2026.09.15-d2fe57e/2062.index.js:2`,
plain model-list formatter (displayModelId/name/default/current/footer). No
provider implementation was copied or bundled. Three production bounds changed;
no UI restructuring, dependency, migration or new operation was needed.

Focused verification:
- `rtk mix test test/cuckoding/cursor_test.exs test/cuckoding/agents_test.exs test/cuckoding_web/agents_live_test.exs`: 12 passed.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked cursor::tests`: 5 passed.
- Native and Elixir checks accept 256/512, reject 513, duplicate late rows and
  malformed/incomplete catalogs. LiveView regression selects/saves all 512 fixture
  entries and assigns the last to Speculator; over-limit saves remain refused.

## Full verification and running artifact

- `rtk mix quality`: 183 tests passed; format, warnings-as-errors compilation,
  Credo, Sobelow and dependency audit passed. Sobelow still emits its existing
  Elixir 1.20 quoted-keyword warnings for Mix.lock; no vulnerabilities found.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`: passed.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`: passed.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`: 49 passed.
- `rtk proxy bin/dev.build`: passed; bundled dylibs are re-signed after the
  expected install_name_tool relocation warnings.
- `rtk proxy bin/smoke`: passed native launch, bootstrap/browser cookie,
  replay/origin rejection, heartbeat, graceful quit and listener cleanup.
  Evidence data: `/private/tmp/ccoding-smoke.klh1wV`.

Retained proof root: `/private/tmp/cuckoding-r020l-proof-x0m8_o_y`.
The read-only SQLite backup `before-catalog.db` passed integrity/foreign keys.
The old R020k shell/BEAM were identified by executable, PID/start identity, cwd,
parent and listener, then stopped gracefully; shell and port cleanup passed.
While stopped, `refresh.exs` started only Repo/PubSub with the existing data and
created/claimed an explicitly authorized `Foundation.inspect_codex` command for
this Cursor connection. It used the new packaged native helper through the real
Cursor adapter, then finished through the normal ledger/projection/event path.
No SQL injection of catalog data, fixture result or inferred authorization was used.
An initial harness startup called a nonexistent PubSub function and exited before
opening Repo or creating a command; corrected to its supervised child spec.

`catalog-receipt.json` records actual command
`4ecd814d-fba5-464e-97a0-b4f254b6addb`: completed, authorization cursor,
source `cursor-cli/models`, **256 fresh entries including 22 Grok variants**,
1,952 ms, fetched `2026-10-10T19:21:57.772260Z`. No model inference occurred.

Launched `/private/tmp/cuckoding-r020l-proof-x0m8_o_y/Cuckoding.app` using the
normal native handshake and unchanged private data at
`/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data`. Shell PID 54791,
BEAM PID 54794; loopback port **59652**. `proof.json` retains their start identities
and native hash. The copied native binary matches the built artifact. After
restart, all 256 catalog entries remain fresh, no command is pending, DB integrity
and foreign keys pass, and migrations, saved model selections, teams, Arenas,
Tabulae and draft/check histories match the pre-refresh backup. Retained test
launchers now point to this bundle with the same data.

The in-app browser blocks the reported localhost URL with ERR_BLOCKED_BY_CLIENT.
No bypass or real interactive browser success is claimed. Automated LiveView
coverage verifies the whole catalog → selection → Save → Team flow; the actual
provider/helper and persisted catalog are verified separately. Cursor inference,
account revocation, physical sleep and clean-machine release remain unverified.

`rtk git diff --check` and changed-document local-link validation passed.
This slice is committed and merged into local main; no remote push/publication.
