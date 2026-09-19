# Cuckoding

Cuckoding is a local-first macOS control plane for orchestrating coding agents across durable, auditable software-development workflows. A developer connects a repository, creates one or more boards, assigns roles such as spec writer, implementer, and reviewer to installed agent runtimes, watches the work move through gates on a visual dashboard, and receives a Git branch ready for human review. Completed work is compressed into reviewed, reusable project knowledge and skills that later runs can use.

Implementation has reached controlled-beta preparation. The repository includes
the loopback-only Phoenix LiveView control plane, durable SQLite workflows,
host runner, supported Codex and Claude Code adapters, plugin and knowledge
boundaries, and the verified native macOS shell. Remaining beta evidence is
tracked in `docs/BETA_REPORT.md` and the ordered tasks under `tasks/`.

For a clean local bootstrap, pinned versions, quality gates, runtime endpoints,
and the verified developer application build, see `docs/DEVELOPMENT.md`.

The static source for [cuckoding.com](https://cuckoding.com) lives in
`github.page/` and deploys to GitHub Pages from `main`.

## Developer build

On Apple Silicon macOS, build the unsigned local application and run its full
sterile launch/update verification with:

```sh
rtk ./bin/dev.build
```

The resulting application is
`desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`. This developer
artifact is for local testing; it is not Developer ID signed or notarized.

## What changed in v2

See `CHANGES.md`. In short: no Docker in the MVP, agents and commands run on the host in confined worktree folders with a local preview URL, a menubar-only native shell with the UI in the default browser, explicit long-running-run and sleep/wake handling, a plugin/connector system for optional tools (XERJ, RTK, Ponytail, MCP servers, container runners), and a knowledge pipeline modeled on current agent-memory practice with dashboard views for knowledge growth and use.

## Product thesis

- Keep source code, credentials, worktrees, and execution local by default.
- Coordinate multiple agent runtimes without pretending they have identical capabilities.
- Make every workflow durable, pausable, resumable, observable, and reviewable — including runs that last hours or days across laptop sleep.
- Isolate feature work with Git worktrees and per-run folders, ports, and process groups; add container isolation later through runner plugins.
- Turn completed-project evidence into approved, reusable knowledge without silently contaminating future projects — and show how that knowledge is used.
- Keep human approval at trust boundaries: configuration changes, destructive operations, knowledge publication, and merge/release.

## Stack

- Elixir/OTP and Phoenix LiveView for orchestration and the real-time UI, served on a loopback port and opened in the user's default browser.
- A thin native menubar shell (Tauri 2 in tray-only mode; alternatives in `docs/DESKTOP_SHELL.md`) that launches the bundled release and offers Cuckoding, About, Settings, Quit.
- SQLite with Ecto for local durable state; Markdown files for human-readable knowledge.
- Git worktrees and a `LocalProcessRunner` for concurrent feature work on the host.
- Launch adapters for Claude Code and Codex, with stable adapter contracts for Cursor Agent and OpenCode.
- A plugin system for connectors: knowledge backends (XERJ, others), shell-output filters (RTK), instruction skills (Ponytail, any `SKILL.md`), MCP servers, and future container runners (Docker, OrbStack, Colima, Apple Containers).
- OpenTelemetry-compatible events and local metric rollups.

## Directory map

| Path | Purpose |
| --- | --- |
| `AGENTS.md` | Binding repository rules for humans and agents |
| `CHANGES.md` | What v2 changed and why |
| `LICENSE` | Apache License 2.0 for the open core and plugin contracts |
| `docs/` | Product, architecture, data, workflow, security, UI, shell, plugins, and knowledge specifications |
| `docs/DOCUMENTATION_AUDIT.md` | Complete documentation inventory, contradictions, risks, and readiness conclusion |
| `docs/IMPLEMENTATION_READINESS.md` | Verified local toolchain, Phase 0 order, blockers, and Phase 1 entry gate |
| `docs/MVP_BOUNDARY_AND_POSITIONING.md` | Launch contract, competitive scan, data defaults, and commercial hypotheses |
| `docs/BETA_RUNBOOK.md` | Safe dogfood protocol, interview guide, knowledge rubric, and beta exit gates |
| `docs/BETA_REPORT.md` | Anonymized run, interview, knowledge, finding, and decision ledger |
| `docs/REFERENCE_CODING.md` | XERJ-backed retrieve-before-code workflow and RTK command convention |
| `docs/TRUSTED_HOST_THREAT_MODEL.md` | Trusted-host boundaries, risks, approvals, tabletop, and residual-risk disclosure |
| `docs/reference-corpus.yml` | Pinned peer repositories, licenses, revisions, and XERJ prefixes |
| `docs/plugins/` | Reference plugin specifications (XERJ, RTK, Ponytail) |
| `tasks/` | Ordered implementation tasks grouped by phase |
| `worklog/` | Durable implementation notes, decisions, and incident records |
| `.cuckoding/` | Example project, workflow, policy, plugin, and role definitions |
| `.agents/skills/` | Repository-local skills for recurring engineering work |
| `bin/dev.build` | Verified unsigned macOS developer application build |
| `github.page/` | Dependency-free public site and its focused verifier |
| `desktop/` | Tray-only Tauri shell, pinned Rust project, local build, and launch verifier |

## How to execute the plan

1. Read `AGENTS.md`, `docs/PRODUCT.md`, `docs/ARCHITECTURE.md`, `docs/SECURITY.md`, and `docs/EXECUTION_ENVIRONMENTS.md`.
2. Start with `tasks/phase-00-discovery/` and complete phases in order unless a task explicitly permits parallel work.
3. Reach the walking skeleton (task 0405) before polishing anything else; it is the first point where the product can be judged.
4. Create one worklog entry for every meaningful implementation session.
5. Record architecture changes in `docs/DECISIONS.md` before changing a settled boundary.
6. Treat task acceptance criteria and verification commands as completion gates.
7. Do not mark a phase complete until its checklist in `docs/PLAN.md` passes.

## Repository shell commands

Prefix every repository shell command with `rtk`. This applies to inspection, Git, Mix, tests, formatters, linters, XERJ, and release checks. Use `rtk proxy <command> ...` only when exact unfiltered streaming output is required or an RTK adapter changes command semantics. Record the exception in the task worklog.

The commands stored in `.cuckoding/project.yml` remain the underlying commands, such as `mix test`. Cuckoding validates the underlying command and its policy first; the optional RTK plugin wraps it afterward. See `docs/REFERENCE_CODING.md` before implementing an unfamiliar problem.

## Pack placement

The `.agents/` and `.cuckoding/` directories are at the repository root, matching the execution and configuration contracts. Do not create nested or duplicate copies. Read `docs/IMPLEMENTATION_READINESS.md` before claiming the first implementation task.

## MVP boundary

The first supported distribution is macOS on Apple Silicon. The MVP is single-user, local-only, and runs agents on the host without container isolation; the runner and provider contracts preserve a path to container runners, remote workers, and team collaboration. Merging and release remain explicit human actions; Cuckoding produces a reviewable branch and draft pull request.

## Source currency

External integration notes were checked against official upstream material on 2026-09-16. Revalidate CLI flags, authentication modes, memory-file layouts, pricing, and packaging details while implementing; these interfaces change independently of this plan.
