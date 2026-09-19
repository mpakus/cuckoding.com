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

## Developer application build

On Apple Silicon macOS, create the unsigned application used for local testing:

```sh
rtk ./bin/dev.build
```

The entrypoint delegates to the one existing desktop build pipeline. It builds
the production Phoenix release, runs the release-metadata and pinned Rust
checks, bundles the Tauri application, and runs the sterile shell verifier. The
verified application is written to
`desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`. This command does
not Developer ID sign, notarize, or create distributable update artifacts; use
`desktop/release.sh` only for an authorized release.

## Project-first onboarding

The dashboard's **Add project** action opens a three-step wizard: project
identity, a native macOS folder chooser and base branch, then review. The local
Phoenix service opens the system chooser, so the browser never uploads or
enumerates the selected folder. Registration accepts an empty folder, an unborn
Git repository, or an existing project. Inspection is read-only until final
confirmation; then Cuckoding initializes Git and creates the first local commit
when needed. Registration records only the project and its first trusted
configuration version, then redirects to project settings. It does not create a
board, task, queued run, feature branch, worktree, port, or provider process.

Project settings can store multiple named agent connections and assign them to
the built-in Specifications, Coding, and Review roles or user-added roles.
Every save appends an immutable configuration revision. The runtime selector
shows Codex, Claude Code, Cursor Agent, OpenCode, and Custom Agent; the Claude
API-key helper is rendered and validated only for Claude Code. Cursor uses a
fresh login in run-owned runtime directories. OpenCode and Custom Agent record
only reviewed machine-local settings, carry an explicit setup-only warning, and
cannot start task runs until their adapter contract and conformance evidence are
complete. Each agent card saves or updates independently; role saves remain a
separate immutable configuration revision.

A project may be registered while its working tree is dirty so the user can
organize existing work. Starting a task remains stricter: the run boundary
requires a clean repository, captures the base revision, snapshots workflow and
role configuration, and only then creates the feature worktree.

The legacy `Cuckoding.GuidedRun` path remains available to the Phase 4 walking
skeleton and tests while project, board, and task setup are separated. It is no
longer a dashboard onboarding surface. Runtime-specific authentication remains
run-scoped: Codex uses a run-owned `CODEX_HOME`; Claude Code requires a reviewed
absolute API-key helper. Cuckoding never infers or stores GitHub credentials in
the project wizard.

## Production release smoke test

Build assets and the release with production configuration:

```sh
rtk env MIX_ENV=prod mix assets.deploy
rtk env MIX_ENV=prod mix release --overwrite
```

The release requires a writable `CUCKODING_DATABASE_PATH` and a unique mode-0600
`CUCKODING_BOOTSTRAP_FILE` containing the per-launch session secret and bootstrap
token. It uses `CUCKODING_PORT` when present and starts the web endpoint only
when `PHX_SERVER=true`. It always binds IPv4 loopback. The desktop shell creates
and deletes the credential file; credentials never appear in argv or ordinary
environment variables.

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

- `/` is the project-first operations dashboard.
- `/projects/new` is the non-executing project registration wizard.
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

For task 0203, XERJ returned the repository's measured PID-plus-start-identity check at `spikes/0004-sleep-wake-power/power_manager_spike.rb:507-510` and Hydra's persisted-agent hydration at `electron/agents/AgentManager.ts:300-351` in pinned MIT revision `d8ad56112c2c3acfb2f65f53b6890f30a25c693c`. Cuckoding keeps the identity check, durable-ID reconstruction, and duplicate-session guard, then adds read-only port/worktree inspection, explicit continue/recover/block events, sleep-gap lease ordering, and a synchronous pre-scheduling gate.

For task 0204, XERJ returned Vibe Kanban's `SecretString` storage and redacted debug formatter at `crates/relay-tunnel/src/server_bin/auth.rs:14-15,58-68` in pinned Apache-2.0 revision `735654971bd396aa97b65166955678e4c34f8bf8`. Cuckoding adapts the non-printing boundary and adds Keychain-backed opaque references, stdin-only writes, value-free access audits, and recursive pre-boundary canary redaction.

For task 0303, XERJ returned Vibe Kanban's structured `git diff --name-status` model and rename/copy parser at `crates/git/src/cli.rs:47-66,215-227,466-509`, plus its approval request path at `crates/executors/src/executors/codex/client.rs:456-499`, in pinned Apache-2.0 revision `735654971bd396aa97b65166955678e4c34f8bf8`. Cuckoding adapts the structured change-list and fail-closed approval boundary, then adds NUL-delimited filenames, both rename paths, trusted configuration snapshots, `.cuckoding/` as an unconditional protected root, exact change-set digests, atomic single-use decisions, and durable audit events.

For task 0304, XERJ returned Vibe Kanban's loopback availability probe and ascending free-port search at `scripts/setup-dev-environment.js:12-36`, and its direct listener bind with OS-selected actual ports at `crates/server/src/main.rs:96-121`, in pinned Apache-2.0 revision `735654971bd396aa97b65166955678e4c34f8bf8`. Cuckoding adapts loopback bind verification but adds a declared project range, durable exclusive lease, database active-port constraint, second OS check, token-free persistence, fixed loopback environment, bounded no-redirect health probe, process/start-identity ownership, and explicit stop/hibernate release.

For task 0305, XERJ returned Vibe Kanban's centralized Git worktree cleanup at `crates/worktree-manager/src/worktree_manager.rs:230-265` in the same pinned Apache-2.0 revision. Cuckoding adapts the single Git-service boundary, but rejects forced deletion and ignored errors: checkpoint ordering, PID/start-identity validation, canonical confinement, marker and revision matching, clean status, no-running-process proof, and retained-artifact events are mandatory.

For task 0306, XERJ returned the repository's accepted clock, assertion, and reconciliation spike at `spikes/0004-sleep-wake-power/power_manager_spike.rb:13-109`. The production manager keeps that measured continuous-minus-uptime algorithm and `caffeinate -i -w` lifecycle, then adds SQLite `power_events`, the existing lease-first reconciler, provider-session eligibility, durable unattended expiry, and pending-approval preservation. The pinned Hydra search supplied no power-specific code to adapt.

For task 0401, project XERJ retrieval returned the runtime spike's explicit grant and sandbox-hash boundary at `spikes/0002-host-runtime/host_runtime_spike.rb:90-136`; the pinned Hydra MIT index confirmed persisted provider session IDs and native resume as adapter boundaries. Cuckoding adapts those ideas into a provider-neutral behaviour with typed requests, explicit requested/enforced/unenforced grants, separate requested and observed models, normalized untrusted events, bounded continuation packages, and a deterministic fake adapter. No peer code was copied.

For task 0402, XERJ returned the repository's redacted host-runtime harness at `spikes/0002-host-runtime/host_runtime_spike.rb:131-235,318-324,390-412` and Hydra's provider preflight/headless/resume split at `electron/agents/providers.ts:4-24,34-81,84-110` in pinned MIT revision `d8ad56112c2c3acfb2f65f53b6890f30a25c693c`. Cuckoding retains only the preflight and native-resume concepts. It adds a pinned fixture vocabulary, strict run-scoped configuration, non-bypass permissions, explicit unenforced restrictions, secret/reasoning filtering, host-runner cancellation, knowledge citations, and the fail-closed OAuth isolation boundary. No peer code was copied.

For task 0403, XERJ returned the accepted runtime spike summary at `docs/HOST_AGENT_RUNTIME_SPIKE.md` and Hydra's Codex native-resume/model-selection boundary at `electron/agents/providers.ts:112-145` in the same pinned MIT revision. Cuckoding adapts only the native session-resume concept. It adds a pinned `0.146.0` JSONL vocabulary, run-scoped `CODEX_HOME` and `AGENTS.md`, strict sandbox and non-interactive approval mapping, disabled network/plugin/hook/subagent surfaces, host-runner cancellation, recursive redaction, explicit tool-grant limitations, and a fail-closed scoped-auth boundary. No peer code was copied.

For task 0404, XERJ returned the accepted Cursor isolation decision at `docs/HOST_AGENT_RUNTIME_SPIKE.md:3-8,34-50,70-78` and Hydra's basic Cursor/OpenCode launch/resume mapping. Cuckoding does not adapt that launch code: the local Cursor evidence violates global state/plugin isolation, and only the OpenCode desktop app is installed. Both integrations are small fail-closed stubs with real binary probes, zero advertised adapter capabilities, and disabled, visibly explained LiveView options.

For task 0405, project XERJ retrieval returned the walking-skeleton, testing, and later release-handoff contracts. The pinned Vibe Kanban implementation at `crates/git/src/cli.rs:368-397` constructs an explicit branch refspec and disables terminal prompting for push at commit `735654971bd396aa97b65166955678e4c34f8bf8` (Apache-2.0). Cuckoding adapts only that bounded push shape and adds a same-run human approval, durable idempotency, local-bare-only validation, clean candidate/ownership checks, non-force behavior, and ordered audit events. No peer code was copied.

The real-provider completion pass also retrieved Agetor's explicit attempt ordinals at `src/shared/types.ts:142-205` in pinned MIT revision `eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a`, plus Vibe Kanban's null stdin at `crates/executors/src/executors/opencode.rs:115-120` and bounded review timeout at `crates/review/src/main.rs:23` in the pinned Apache-2.0 revision above. Cuckoding independently applies those behaviors through durable failed attempts, monotonic retry numbers, immediate noninteractive stdin EOF, and a validated adapter wall limit. Its stricter host boundary still owns candidate commits and approved pushes; no peer code was copied.

For task 0501, the local XERJ node was unavailable, so the pinned checkouts were inspected directly and the degraded retrieval is recorded in the worklog. Vibe Kanban's closed task vocabulary at `crates/db/src/models/task.rs:7-24` and Agetor's finite recovery-attempt metadata at `src/shared/types.ts:142-205` confirmed the useful boundaries. Cuckoding keeps lifecycle states separate from versioned stage graphs and implements its own normalized validator, finite budgets, labeled transition evaluator, cycle safety, and finding routing. No peer code was copied.

For task 0502, the local XERJ node remained unavailable, so the pinned Vibe Kanban checkout was inspected directly. Its workspace preferences at `crates/db/src/models/scratch.rs:132-152` persist project and Kanban filters in the database. Cuckoding uses URL query parameters instead, giving the single-user local board reloadable and shareable filters without a new preference table. The accessible native transition controls, server-authorized drag targets, durable command outcomes, and edit audit event are independent implementations; no peer code was copied.

For task 0503, the local XERJ node remained unavailable, so the pinned peers were inspected directly. Hydra's `electron/agents/AgentManager.ts:168-176` and `electron/agents/AgentManager.test.ts:298-317` enforce and verify a hard active-agent cap. Agetor's `src/bun/claude-tmux-queue.test.ts:660-688` verifies that independent task queues do not block each other. Cuckoding adapts those two behaviors into layered durable admission and cross-board fairness, then adds dependencies, trusted project limits, memory/port probes, unattended approval notification keys, and safe board-control behaviours. No peer code was copied.

For task 0504, the local XERJ node remained unavailable, so pinned Agetor revision `eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a` was inspected directly under its MIT license. `src/bun/github.ts:60-120,1610-1650` constrains the API origin, requires a credential, validates PR inputs, and sends a draft-PR payload. Cuckoding adapts that trust boundary while adding typed hash-verified evidence, protected-branch refusal, same-run human approval, opaque `SecretStore` references, host-only Git authentication, value-free audit records, and fixture-injected network tests. No peer code was copied.

For task 0601, the local XERJ node remained unavailable, so pinned Vibe Kanban revision `735654971bd396aa97b65166955678e4c34f8bf8` was inspected directly under Apache-2.0. `crates/utils/src/msg_store.rs:37-119` retains bounded in-memory history and combines it with a broadcast stream, but logs and drops subscriber lag. Cuckoding adapts the history-plus-live interface while replacing volatile history with redacted append-only SQLite rows, gapless per-stream sequences, post-commit PubSub hints, subscribe-before-catch-up reads, durable-ID deduplication, and explicit sleep-gap/stale UI text. No peer code was copied.

For task 0602, the local XERJ node remained unavailable, so the project and pinned Hydra revision `d8ad56112c2c3acfb2f65f53b6890f30a25c693c` were inspected directly under their existing licenses. The project identity check in `lib/cuckoding/execution/local_process_runner.ex` was the applicable source; Hydra had no process-resource pattern to adapt. Cuckoding extends its verified PID/start-identity boundary to the owned process group, records cumulative CPU, RSS, process count, and listening ports without interpolation, keeps stage active and wall time separate, and explicitly labels host limits unenforced. No peer code was copied.

For task 0603, the local XERJ node remained unavailable, so pinned MIT sources were inspected directly. Agetor revision `eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a` validates usage independently from optional cost at `src/bun/fx-acp.ts:1832-1856`; Hydra revision `d8ad56112c2c3acfb2f65f53b6890f30a25c693c` labels its dashboard as local-log analysis and normalizes token/cost dimensions at `src/components/UsageDashboard/UsageDashboard.tsx:86-89,346-370`. Cuckoding adapts the separation principle, then adds immutable effective-dated catalogs, integer formulas, explicit billing mode, session-scoped replay protection, independent usage/cost provenance, and append-only plugin claims. No peer code was copied.

For task 0604, the local XERJ node remained unavailable, so pinned Hydra revision `d8ad56112c2c3acfb2f65f53b6890f30a25c693c` was inspected directly under its MIT license. Its status-aware agent cards and grouping patterns appear at `src/components/Sidebar/AgentItem.tsx:32-175`, `src/components/GridView/TerminalTile.tsx:80-165`, and `src/components/GridView/GridView.tsx:240-330`. Cuckoding adapts only the visible status, grouping, and inspection ideas. Its own implementation uses durable database projections, bounded fixed-query retrieval, native links and selects, table alternatives, coalesced refreshes, and no mutating control without a live ownership handle. The pinned Vibe Kanban source contained no more applicable UI pattern, and no peer code was copied.

For task 0701, the local XERJ node remained unavailable, so the pinned peers were inspected directly. Agetor revision `eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a` reads Markdown front matter only from a successfully readable project-tree file and keeps project/global source identity explicit at `src/bun/commands.ts:49-119,300-356` (MIT). Cuckoding adapts only those file-authority and scope-separation ideas. It adds a strict bounded schema, exact-byte hashes, confined non-symlink paths, durable mismatch states, explicit higher-version user acceptance, required global review, and project authorization before path resolution. No peer code was copied.

For task 0702, the local XERJ node remained unavailable and direct inspection of pinned MIT Agetor plus Apache-2.0 Vibe Kanban found no knowledge-extraction pipeline to adapt. Cuckoding therefore follows its own documented boundary: only normalized public events and artifact descriptors enter a bounded fixed template; redaction runs before and after the recorded run adapter; the control plane assigns evidence and classifies memory operations; and a failed job cannot leave partial candidates. No peer code was copied.

For tasks 0802 and 0803, the local XERJ node remained unavailable. Direct
inspection of pinned Apache-2.0 Vibe Kanban
`crates/executors/src/executors/mod.rs:222-285` and
`crates/executors/src/executors/qa_mock.rs:1-85` informed explicit contracts
with deterministic fakes. Pinned MIT Agetor
`src/bun/commands.ts:380-420,610-682` informed scoped MCP discovery and
credential-free descriptions. Cuckoding adds current durable activation,
signed run-scoped grants, closed/redacted outputs, source-labeled numbers,
server-derived namespaces, offline exact-package configuration, and tool
allowlists. No peer code was copied.

For task 1002, the local XERJ node was unreachable, so pinned MIT Agetor
revision `eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a` was inspected directly.
Its abortable full-jitter stream retry at `src/cli/sse.ts:112-130` remains an
adapter-layer option only after Cuckoding durably records the sleep gap,
extends leases, and performs one idempotent reconciliation. The drill reuses
the repository's existing lifecycle, power, reconciler, and release fixtures;
no peer code was copied.
