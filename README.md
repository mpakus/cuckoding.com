# AgentDesk

AgentDesk is a local-first desktop workspace for running multiple coding agents on the same Git project. Each agent works in its own tab while an Elixir/OTP coordinator provides built-in agent-to-agent discovery, task delegation, durable messages, artifacts, handoffs, resource leases, and project memory.

`AgentDesk` is a working name.

## Status

Phases 0–6 of `docs/PLAN.md` are implemented except wrapping a Mix release in ExTauri/Burrito on OTP 28. Post-MVP work through ADR-024 is in tree: search/memory, hardening, multiple open projects, glob leases, review/merge queue, task graphs, roles, SDK/remote attach, usage, optional Compose, and file-based team sync. The public A2A gateway remains deferred.

Dev path: `mix phx.server` on [http://127.0.0.1:4000](http://127.0.0.1:4000), or `mix ex_tauri.dev`. See `docs/README.md`.

## Prerequisites

- Elixir 1.15+ (developed on Elixir 1.19 / OTP 28)
- Rust toolchain and Tauri prerequisites for the desktop shell
- Git with worktree support

Provider CLIs (Codex, Claude Code, Cursor `agent`, OpenCode) are discovered from the machine; AgentDesk does not collect provider passwords.

## Setup

```bash
mix setup
mix phx.server
```

Open [http://127.0.0.1:4000](http://127.0.0.1:4000). The HTTP listener binds to loopback only.

Desktop development:

```bash
mix ex_tauri.dev
```

## Quality gates

```bash
mix test
mix check
```

`mix check` runs format, compilation with warnings as errors, tests, Credo, Dialyzer, and Sobelow.

## Documentation

| File | Purpose |
| --- | --- |
| [AGENTS.md](AGENTS.md) | Working rules for coding agents |
| [docs/README.md](docs/README.md) | Product overview and MVP boundary |
| [docs/PLAN.md](docs/PLAN.md) | Delivery phases and acceptance criteria |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Processes, data flow, and failure boundaries |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Bootstrap and local conventions |
| [docs/RELEASE.md](docs/RELEASE.md) | Packaging and signing checklist |
| [docs/OPERATIONS.md](docs/OPERATIONS.md) | Backup, migrations, team sync files |
