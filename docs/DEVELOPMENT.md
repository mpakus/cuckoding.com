# Development Guide

## 1. Prerequisites

Use versions supported by the selected ExTauri release and pin them in the repository tool-version file after Phase 0 verification.

Expected toolchain:

- Elixir and Erlang/OTP;
- Rust toolchain and Tauri platform prerequisites;
- Phoenix and Node tooling required by the generated assets pipeline;
- Git with worktree support;
- Codex CLI for Codex integration development;
- Claude Code for Claude integration development;
- Cursor CLI (`agent`) for Cursor integration development;
- OpenCode CLI (`opencode`) for OpenCode integration development;
- optional XERJ binary;
- macOS signing tools for distribution work.

ExTauri's reviewed documentation requires Elixir 1.15 or newer with OTP 27 and packages the BEAM application with Burrito. Verify the current requirement rather than relying on this document during future upgrades.

## 2. Bootstrap sequence

The Phoenix application lives at the repository root (`:agent_desk`, module `AgentDesk`). ExTauri scaffolding is in `src-tauri/`.

```bash
mix setup
mix phx.server
```

The HTTP listener binds to `127.0.0.1:4000`. Desktop window:

```bash
mix ex_tauri.dev
```

Do not pin dependency versions in documentation before the spike confirms compatibility. Pin them in `mix.exs`, `mix.lock`, Cargo lockfiles, and the repository tool-version configuration.

## 3. Proposed source layout

```text
lib/
├── agent_desk/
│   ├── application.ex
│   ├── projects/
│   ├── agents/
│   ├── tasks/
│   ├── a2a/
│   │   ├── agent_card.ex
│   │   ├── agent_directory.ex
│   │   ├── context.ex
│   │   ├── delegation.ex
│   │   ├── task_coordinator.ex
│   │   ├── message.ex
│   │   ├── message_router.ex
│   │   ├── delivery.ex
│   │   ├── artifact.ex
│   │   ├── artifact_registry.ex
│   │   └── idempotency.ex
│   ├── coordination/
│   ├── providers/
│   │   ├── adapter.ex
│   │   ├── acp/
│   │   ├── codex/
│   │   ├── claude/
│   │   ├── cursor/
│   │   ├── opencode/
│   │   └── fake/
│   ├── git/
│   ├── search/
│   ├── security/
│   └── telemetry.ex
├── agent_desk_web/
│   ├── components/
│   ├── live/
│   └── router.ex
└── agent_desk_mcp/
    ├── endpoint.ex
    ├── tools/
    │   ├── a2a/
    │   ├── resources/
    │   └── search/
    └── authorization.ex

priv/
├── repo/migrations/
├── provider_fixtures/
└── static/

test/
├── agent_desk/
├── agent_desk_web/
├── agent_desk_mcp/
└── support/
```

Keep contexts cohesive; do not create a directory for every individual module without a clear boundary.

## 4. Configuration

Configuration classes:

- compile-time application identity and bundled capabilities;
- runtime application-data paths and local ports;
- project-specific settings in SQLite;
- provider discovery paths and permission profiles;
- feature flags for XERJ and experimental adapters.

Secrets must come from protected environment/OS storage and must not be committed.

Suggested feature flags:

```elixir
config :agent_desk, :features,
  xerj: false,
  shared_workspace_mode: false,
  raw_provider_events: false,
  generic_pty: false
```

Internal A2A is core behavior and must not have an off switch. Project policy may restrict autonomous delegation, but peer registration, durable routing, and user-visible coordination remain available.

Suggested runtime policy shape:

```elixir
config :agent_desk, :a2a,
  max_delegation_depth: 3,
  max_delegation_fan_out: 4,
  max_open_proposals_per_agent: 4,
  idempotency_ttl_hours: 24,
  default_message_ttl_seconds: 86_400
```

## 5. Development commands

Expected commands once the project exists:

```bash
mix setup
mix phx.server
mix ex_tauri.dev
mix test
mix format
mix credo --strict
mix dialyzer
mix sobelow
```

Add aliases such as `mix check` only when they remain transparent and reproduce the CI gates.

## 6. Test data safety

- Use temporary Git repositories for worktree tests.
- Use temporary application-data roots.
- Never point cleanup tests at a user's home directory or real repository.
- Validate every temporary path before recursive deletion.
- Use the fake provider for the default test suite.
- Live-provider tests are explicit and opt-in.

## 7. Provider development

For each installed provider:

1. record version;
2. generate or capture the supported protocol schema where available;
3. add sanitized fixtures;
4. implement normalization;
5. test process interruption and exit;
6. test per-session MCP injection;
7. document capability differences.

For Cursor and OpenCode, run both the shared ACP transport contract suite and the provider-specific fixture suite. A passing Cursor fixture does not prove that the installed OpenCode version has the same methods or semantics, or vice versa.

Every first-class provider adapter must also pass the same internal A2A bootstrap/delivery suite: automatic Agent Card registration, pending-inbox load, safe-boundary injection, acknowledgement, termination handling, and resume without duplicate delivery.

Do not make CI depend on whatever provider version happens to be installed on a developer machine.

## 8. Internal A2A development

- Keep internal structs and Ecto schemas provider-neutral.
- Treat the public A2A 1.0 specification as semantic guidance and future adapter input, not as the internal persistence schema.
- Route all agent calls through MCP tool modules into `AgentDesk.A2A.*`; never call provider adapters peer-to-peer.
- Put authorization and identity derivation before changeset/domain execution.
- Canonicalize and hash validated input before idempotency lookup.
- Commit state plus normalized event before PubSub notification.
- Assign monotonic inbox sequence transactionally per recipient.
- Keep PubSub subscriptions ephemeral and make reconnect load canonical task/inbox state.
- Store artifact bytes outside hot relational rows and verify their hash before publication.
- Add deterministic clock/UUID injection for expiry, retry, and race tests.
- Maintain an explicit mapping module for any future public A2A gateway so wire-version changes cannot leak into core modules.

No external A2A SDK is required for the internal MVP.

## 9. Database development

- Keep migrations small and reversible where practical.
- Test migration from an empty database and the previous released schema.
- Never edit a released migration.
- Use changesets and database constraints together.
- Inspect SQLite query plans for timeline and inbox queries before large-scale optimization.

## 10. Documentation changes

Update:

- `ARCHITECTURE.md` for component or boundary changes;
- `DB.md` for schema/invariant changes;
- `A2A.md` for discovery, delegation, messages, tasks, artifacts, delivery, or federation boundaries;
- `PROTOCOL.md` for MCP/event changes;
- `PROVIDERS.md` for provider behavior;
- `SECURITY.md` for permission or trust-boundary changes;
- `DECISIONS.md` for accepted architectural tradeoffs;
- `PLAN.md` as phases complete.

## 11. Release preparation

- run all CI gates;
- run desktop packaging smoke tests;
- verify child-process cleanup;
- verify pending A2A delivery/delegation recovery and idempotent restart;
- verify migrations against a copy of the previous database;
- update third-party notices;
- sign and notarize macOS artifacts;
- test install and upgrade on a clean user account;
- confirm that development listeners and debug features are disabled.
