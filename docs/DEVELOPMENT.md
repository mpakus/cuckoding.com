# Development

## Supported toolchain

Task 0101 pins the application foundation to versions verified from official upstream metadata on 2026-09-17.

| Component | Version |
| --- | --- |
| Erlang/OTP | 28.4 |
| Elixir / Mix | 1.19.5 compiled for OTP 28 |
| Phoenix / `phx_new` | 1.8.14 |
| Phoenix LiveView | 1.2.12 |
| Ecto SQL / SQLite3 adapter | 3.14.0 / 0.24.1 |
| Tailwind wrapper / binary | 0.5.1 / 4.2.1 |
| Esbuild wrapper / binary | 0.10.0 / 0.25.4 |
| Bandit | 1.12.5 |

The exact Erlang and Elixir versions are in `.tool-versions`; direct and transitive Elixir dependencies are fixed by `mix.exs` and `mix.lock`. Updating any pin is an explicit maintenance change with the full quality gate. Tailwind 4.3.0 was evaluated but its official arm64 binary was terminated by macOS before startup; 4.2.1 is the newest verified compiler for this target.

## Clean bootstrap

From a clean checkout with RTK available:

```sh
rtk mix setup
rtk mix quality
rtk mix phx.server
```

`mix setup` fetches dependencies, installs the pinned Tailwind and esbuild binaries, and builds assets. `mix quality` runs the formatter check, warnings-as-errors compilation, tests, Credo, Sobelow, and the Hex retirement audit. The server listens only on `127.0.0.1:4000`; open `http://127.0.0.1:4000`.

## Production release smoke test

Build assets and the release with production configuration:

```sh
rtk env MIX_ENV=prod mix assets.deploy
rtk env MIX_ENV=prod mix release --overwrite
```

The release requires `CUCKODING_SECRET_KEY_BASE` and a writable `CUCKODING_DATABASE_PATH`, uses `CUCKODING_PORT` when present, and starts the web endpoint only when `PHX_SERVER=true`. It always binds IPv4 loopback. Never commit or print the production secret; the native shell bootstrap in task 0901 will provide it through the approved launch boundary.

SQLite connections use WAL journaling, foreign keys, a 5-second busy timeout, synchronous `NORMAL`, and immediate write transactions. `mix setup` creates and migrates the development database; `mix test` creates and migrates the disposable test database before running tests.

## Context boundaries

The foundation declares boundaries without implementing workflows prematurely:

| Context | Responsibility |
| --- | --- |
| `Cuckoding.Projects` | Project identity and configuration revisions |
| `Cuckoding.Workflows` | Workflow definitions, boards, tasks, approvals, and transitions |
| `Cuckoding.Execution` | Durable commands, runs, attempts, leases, and host execution |
| `Cuckoding.Adapters` | Replaceable agent-runtime contracts and normalized results |
| `Cuckoding.Plugins` | Plugin manifests, activation, capabilities, and health |
| `Cuckoding.Knowledge` | Knowledge provenance, review, publication, and retrieval |
| `Cuckoding.Power` | Assertions, sleep-gap detection, and wake reconciliation |
| `Cuckoding.Telemetry` | Activity, measurements, estimates, and diagnostics |
| `Cuckoding.Shell` | Authenticated native-shell/control-plane boundary |

Durable schemas and commands begin in task 0102. LiveViews render context results; they do not own workflow state.

## Runtime surfaces

- `/` is the basic LiveView status shell.
- `/health` reports application and dependency health separately.
- `/status` adds an allowlisted configuration snapshot; sensitive configuration is never inspected wholesale.
- Requests receive `x-request-id` and matching `x-correlation-id` response headers, and both identifiers are included in key-value log metadata.

Use `Cuckoding.Correlation.capture/0` before spawning work and `with_context/2` inside the child process. Emit application telemetry through `Cuckoding.Correlation.execute/3` so the current public correlation ID is carried without copying Logger process metadata by hand.

The injected `Cuckoding.Clock` behaviour supplies wall and monotonic time. Tests use `Cuckoding.TestClock`; durable code must not call system time directly when behavior depends on time.

## Reference coding

The local XERJ search for task 0101 returned the existing loopback endpoint at `spikes/0003-menubar-release/control_plane/lib/cuckoding_shell_spike/endpoint.ex:1-27` and Vibe Kanban's request-ID and health route at `crates/remote/src/routes/mod.rs:161-183` in pinned revision `735654971bd396aa97b65166955678e4c34f8bf8` (Apache-2.0). This foundation adapts only the patterns: loopback service boundaries, propagated request IDs, and a small versioned health response. Cuckoding adds separate dependency health, correlation metadata, secret-safe diagnostics, and the repository's release constraints.

For task 0102, XERJ returned Agetor's WAL, synchronous `NORMAL`, and foreign-key setup at `src/bun/db.ts:61-73` in pinned revision `eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a` (MIT). Cuckoding adapts those SQLite durability settings through the official Ecto SQLite3 adapter and adds a busy timeout, immediate write transactions, append-only event triggers, transactional per-run sequencing, and a durable idempotent command ledger.

For task 0103, XERJ returned Hydra's persisted-agent hydration at `electron/agents/AgentManager.ts:300-346` in pinned revision `d8ad56112c2c3acfb2f65f53b6890f30a25c693c` (MIT). Cuckoding adapts only the restart principle: reconstruct volatile workers from durable identifiers and reset transient state. Cuckoding keeps lease ownership in SQLite, hashes bearer tokens, orders sleep-gap extension before expiry, and uses OTP registry/supervision rather than an in-memory agent map.

For task 0201, XERJ returned Vibe Kanban's explicit UUID-backed task record at `crates/db/src/models/task.rs:1-56` in pinned revision `735654971bd396aa97b65166955678e4c34f8bf8` (Apache-2.0). Cuckoding adapts the relational identity pattern while adding its board/run/attempt hierarchy, UUIDv7 command boundary, database enum checks, DAG rejection, immutable snapshots, and partial ownership indexes.

For task 0202, XERJ returned Vibe Kanban's closed `TaskStatus` enum at `crates/db/src/models/task.rs:7-20` in the same pinned Apache-2.0 revision. Cuckoding adapts the explicit state vocabulary, then adds guarded transition graphs, same-transaction task/run projections and public events, persisted idempotent outcomes, required wait reasons, and separate active/wall timing.
