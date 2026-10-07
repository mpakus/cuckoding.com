# R010 — Local application foundation

Status: complete, verified for local main integration. Branch:
`feature/r010-local-foundation`.
Acceptance: [R010](../tasks/R010-local-foundation.md).

## Baseline and guidance

- User authorized implementation and local main integration after each completed
  plan slice. Committed/fast-forwarded R001 as `b6523ce`; no remote publication.
- Read the six core contracts, plan, UI/reference guidance, Ponytail full 4.13.0
  (MIT), and Elixir/LiveView, shell, local-runner, architecture, security and
  quality-gate skills. No subagents requested or used.
- Reset leaves no application implementation. Generate a fresh minimal Phoenix
  foundation; do not restore historical product code. Retain the prior license.
- Existing runtime: OTP 28 / ERTS 16.4; select installed Elixir built for OTP 28.
  Rust 1.97.1 and Tauri CLI 2.11.4 are installed. Record final locked versions below.
- Official references: Phoenix installation/generator, Ecto SQLite transaction
  modes/defaults and Tauri 2 tray APIs. Inspect dependency source/license at the
  selected versions before adapting the relevant mechanisms.
- RTK proxy exceptions: complete source reads, machine-readable Git metadata,
  dependency/build output and shell/native smoke protocols need unfiltered output.
  All repository shell entrypoints remain prefixed with RTK.

## Implementation

- Fresh Phoenix/LiveView/Tailwind foundation and Ecto/SQLite migration. Setup
  commands have UUID keys, expected revisions, bounded leased attempts and
  transactionally appended events; the dispatcher recovers from a killed worker.
- Private rebuild marker/data root, old-data/symlink refusal, schema downgrade
  refusal, WAL/FK and five-second native busy handler. The old application and
  databases were not stopped, read or migrated.
- Thin Tauri 2 tray, menu handlers, bundled release/process group, exclusive
  storage lock, clean environment, private bootstrap file, one-time browser
  handoff, encrypted expiring session, origin/host/CSRF/CSP controls and graceful
  owned shutdown. No provider processes or imported personal credentials.
- Minimal responsive setup UI with honest metadata-only tool discovery, RTK
  required/Ponytail full defaults, persisted activity and reconnect from SQLite.
  Vendored Ponytail 4.13.0 instructions and its MIT license; no new plugin needed.
- Build and smoke scripts, bundled/relocated OpenSSL runtime and license, pinned
  toolchains/lockfiles. README, AGENTS and architecture/data/security/development/
  testing/plan documents describe actual R010 scope separately from the roadmap.

## Sources and compatibility findings

- Phoenix generator 1.8.13 (MIT): generated a temporary minimal SQLite project,
  retained standard Repo/error modules and small test helpers; no old product
  implementation was restored. Runtime Phoenix is locked at 1.8.15; LiveView
  1.2.12. Official references: [installation](https://hexdocs.pm/phoenix/installation.html),
  `deps/phoenix/lib/phoenix/socket/transport.ex:341` (origin checks) and `:515`
  (session/CSRF), `deps/phoenix_live_view/lib/phoenix_live_view/socket.ex:98`.
- SQLite adapter 0.25.0 (MIT), `deps/ecto_sqlite3/lib/ecto/adapters/sqlite3.ex:210`
  immediate transactions. `deps/exqlite/lib/exqlite/connection.ex:540` explains
  why a custom busy handler makes `PRAGMA busy_timeout` read zero; test the
  configured native timeout instead of replacing it with a PRAGMA handler.
- Tauri 2.11.5 (MIT/Apache-2.0), official [tray API](https://v2.tauri.app/learn/system-tray/)
  and registry `tauri-2.11.5/src/tray/mod.rs:386,421` for build/retention. Cargo's
  newer caret-compatible internals failed compilation; lock macros/codegen
  2.6.3, utils 2.9.3, runtime 2.11.3 and runtime-wry 2.11.4 with the 2.11.5 core.
- Elixir 1.20.3-otp-28 / OTP 28.5, Rust 1.97.1, cargo-tauri 2.11.4. The system's
  other Cargo 1.83 cannot parse these dependencies; the build script puts rustup
  first on PATH. Rust stripping produced a verified LINKEDIT string pool offset
  382316 (remainder 4 instead of 0); disable stripping per
  [rust-lang/rust#157750](https://github.com/rust-lang/rust/issues/157750).
- Tailwind 4.3.0 from the official release had an invalid ad-hoc signature
  (`codesign --verify` failed; execution returned 137). Local re-signing in the
  build script resolves it without changing OS protections. Generated resource
  copies are owner-writable so subsequent Tauri builds can replace staged OTP
  and OpenSSL files. Assets use esbuild 0.25.4.
- Ponytail instruction SHA-256:
  `1316a2f3f95741d2300b116fe0c2d81ce4a9568656ed0a62643f54aaf09957f2`.
  Temporary C glyph artwork is the repository SVG; generated its required PNG
  with `rtk cargo tauri icon priv/static/favicon.svg --output /private/tmp/ccoding-r010-icons`.

## Verification evidence

All commands were run from the repository root unless noted. `rtk proxy` was
used for exact source, shell script/env, native protocol and diagnostic output.
No authentication value, cookie or private environment was printed.

| Command / check | Result |
| --- | --- |
| `rtk mix format` then `rtk mix quality` | Pass: format, application compile with warnings as errors, **22 tests**, Credo strict, Sobelow, dependency audit |
| `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check` | Pass |
| `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked` | **4 passed** |
| `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings` | Pass, no issues |
| `rtk proxy bin/dev.build` | Built local `CCoding.app` with bundled OTP, assets and relocated OpenSSL; repeat-build permission fix included |
| `rtk proxy bin/smoke` | Native release launch/bootstrap/handoff/heartbeat/quit/listener cleanup passed; fresh roots `/private/tmp/ccoding-smoke.0cqhJ3` and `.48J19p` |
| `rtk cargo build --manifest-path desktop/src-tauri/Cargo.toml --locked` | Debug executable built with expanded real-HTTP smoke assertions |
| `rtk proxy env CCODING_RELEASE_DIR='/Users/mpak/www/elixir/cuckoding.com/desktop/src-tauri/target/release/bundle/macos/CCoding.app/Contents/Resources/release' CCODING_DATA_DIR=/private/tmp/ccoding-r010-http-smoke desktop/src-tauri/target/debug/ccoding --smoke-test` | Pass: cookie protections, authenticated page, unauthorized redirect, replay 401, foreign-origin 403, shutdown |
| Read-only Python SQLite check of smoke DB | Integrity `ok`, 0 FK violations, DB mode 0600; public shell/browser/quit events retained |
| Same real-HTTP smoke run twice against its isolated DB | Pass: both launch/browser/quit sequences retained (6 events), integrity still `ok` |
| `otool -L` scan of bundled native libraries | No Homebrew runtime dependencies remain; crypto resolves bundled libcrypto |
| Python local-link check over README, AGENTS, docs, skills and task | 32 documents, no missing targets |
| `rtk git diff --check` | Pass |

Initial failures resolved: migration pool size 1 deadlocked its own lock/query;
path-component accumulation lost the absolute root; newer-schema detection must
read migration filenames instead of including applied unknown versions; restart
test must kill between SQL calls rather than disconnect its Sandbox owner; retry
exhaustion now broadcasts committed failure; sessions recheck incoming updates.
Native dependency, icon, borrow lifetime and build-tool fixes are listed above.

Sobelow's limited reviewed exceptions are in `docs/SECURITY.md`. It emits
Elixir 1.20 parser warnings for standard generated Mix.lock keys; compilation
itself passes. Phoenix Ecto also emitted its upstream xref deprecation warning
on first dependency compile; no application compiler warnings remain.

## Final artifact and browser acceptance

- Final `rtk proxy bin/dev.build` passed after adding automatic browser opening
  on shell startup and retaining native disclosure `open` state across LiveView
  updates (`JS.ignore_attributes`). Regression assertion is in the LiveView test.
- Final `rtk proxy bin/smoke` passed including cookie protection, unauthorized
  access, handoff replay, foreign origin, heartbeat, graceful quit and listener
  cleanup. Data retained at `/private/tmp/ccoding-smoke.J5bHhu`.
- Native executable SHA-256:
  `39f09fcde973124a6c2196da34051a04bb079e492b981d41debf940dc8213da2`.
  Artifact: `desktop/src-tauri/target/release/bundle/macos/CCoding.app`.
- Actual Chrome inspection: authenticated browser opens automatically; Check
  setup discovers Codex/Claude/Cursor/RTK by metadata; Hermes is missing. Recheck
  retains expanded Location; browser reload preserves discovery; Tab/Return opens
  the disclosure; 390×844 responsive layout remains usable. Desktop inspected.
- Controlled shell-loss drill signalled only the verified owned test shell
  PID 92634; its server on 50962 closed after the heartbeat deadline. The unrelated
  existing BEAM on 4000 was left untouched. Relaunched the final bundle; browser
  listener observed at `127.0.0.1:52279`. These are historical observations, not
  future process identities or restart targets. The final app is left running.
- Computer use cannot attach to a windowless Tauri app, so no physical tray Quit
  click is claimed. The actual shutdown implementation and owned listener cleanup
  passed the packaged native smoke; shell disappearance passed separately.

No real provider, clean-machine install, signing/notarization, physical sleep,
upgrade migration, ten-minute onboarding, roles, Arena, Tabula or battle evidence
is claimed. Those remain R020–R100. Local merge is authorized; no push/publication.
