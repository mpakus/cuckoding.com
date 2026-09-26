# Cuckoding

Cuckoding coordinates coding agents on your Mac through **Speculator → Implementor → Reviewer** workflows. Connect a local repository, assign saved agents to a board, start development, and follow progress, evidence and controls in a live dashboard. Work runs in separate Git worktrees; reviewed results stay on local branches until a separately approved release. Project knowledge can be reviewed and reused by later runs.

The source is in **controlled-beta preparation**, with no accepted public MVP
release. The repository includes
the loopback-only Phoenix LiveView control plane, durable SQLite workflows,
host runner, implemented Claude Code, Codex, and Cursor Agent launch adapters,
plugin and knowledge boundaries, and a native macOS shell. The latest board
controller has local regression and desktop/mobile browser evidence; real-provider,
physical sleep/wake and packaged-app acceptance remain open. Editing this source
does not update an installed application. See the
[implementation evidence](worklog/2026-09-25-1049-board-controller.md) and
[beta ledger](docs/BETA_REPORT.md).
The current [release-readiness decision](docs/RELEASE_READINESS.md) is no-go
until a fresh signed candidate and the outstanding provider/beta gates pass.

## Start work

1. In **Agents**, save a supported runtime, authorize its app-owned provider
   profile and select a model. Claude Code, Codex and Cursor Agent have launch
   adapters; OpenCode and Custom Agent are setup-only.
2. **Add project**, review its local folder and base branch, then assign the saved
   agents to project roles. Create a board or explicitly apply roles to an existing
   one. Registration creates no task or agent process.
3. Add Draft cards, or ask an assigned agent to propose tasks from project
   Markdown. Review and import selected proposals before execution.
4. Choose how to run the work:

| Action | Scope and order | Completion and code base |
| --- | --- | --- |
| **Start board** | Fixed snapshot of current Draft/Ready cards; one delivery task at a time, dependencies first, then descending priority | Explicit automatic local completion after passing review; each task starts from the latest reviewed batch commit |
| **Start project** | Eligible Ready tasks across unclaimed boards, up to board/project/machine limits | Manual completion by default, optional automatic local completion; independent task bases, without the board's reviewed commit chain |
| **Prepare run → Start workflow** | One Ready task on an unclaimed board | Reviewed manual start, the same admission checks, and an explicit completion choice |

For **Start board**, review the queue, saved roles/models, budgets, dependencies,
exclusions and clean project revision, then authorize local completion. The
assigned Speculator proposes each next step; Cuckoding validates it. New cards
wait for another batch. The first hard blocker requires attention.

The board provides **Pause, Resume, Stop, Skip, Retry** and a confirmed **Refresh**
of pending requests. Skip preserves changes and history and defers dependent
descendants; incomplete work never counts as Done. The home dashboard mirrors
batch progress, while run pages and Agent Floor expose evidence, agent sessions
and resource observations. Statistics include controller sessions and retries,
with missing measurements and estimated costs labeled.

Read the [board controller guide](docs/CUCKODING-CONTROL.md) for the full contract.
Push, PR creation, merge, policy expansion and global knowledge publication keep
their separate approval boundaries. The host runner uses provider permissions
and owned process groups; it is **not a sandbox**.

## Develop locally

Use the pinned Elixir/OTP versions in `.tool-versions` and RTK for repository
commands. Start the local development server with:

```sh
rtk mix setup
rtk mix quality
rtk env PHX_SERVER=true mix phx.server
```

Open `http://127.0.0.1:4000`. Setup creates/migrates the development database and
builds assets. See [Development](docs/DEVELOPMENT.md) for the toolchain, runtime
endpoints, isolated fixtures and safe upgrades of existing application data.

The static source for [cuckoding.com](https://cuckoding.com) lives in
`github.page/` and deploys to GitHub Pages from `main`.

### Native developer build

On Apple Silicon macOS, build the unsigned local application and run its full
sterile launch/update verification with:

```sh
rtk ./bin/dev.build
```

The resulting application is
`desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`. This developer
artifact is for local testing; it is not Developer ID signed or notarized.
When replacing an older developer bundle that has existing data, follow the
backup-first migration procedure in `docs/DEVELOPMENT.md`; signed updates use
the application's guarded updater instead.

## Background

[CHANGES.md](CHANGES.md) records the v2 direction: host execution, a menubar shell
with browser UI, durable long-running workflows, optional tool plugins, and
reviewed project knowledge. Current behavior and acceptance limits are described
in [Product](docs/PRODUCT.md), [Flow](docs/FLOW.md) and [Release readiness](docs/RELEASE_READINESS.md).

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
- Launch adapters for Claude Code, Codex, and Cursor Agent, with a stable adapter contract for OpenCode.
- Saved agents at **Agents** (`/settings/agents`): authorize Codex/Cursor once and reuse the sign-in across named agents and projects, each with its own model and role assignments. Separate sign-ins are optional; shared profiles also share provider history. Runs retain separate permissions/worktrees. See [authorization flow and acceptance limits](docs/AGENT_AUTHORIZATION_FLOW.md).
- Durable failures: agent sign-in/disconnect errors remain in the Agents page, while planning and delivery failures remain on the run page with a safe error code, timeline, and redacted live/full process logs.
- A plugin system for connectors: knowledge backends (XERJ, others), shell-output filters (RTK), instruction skills (Ponytail, any `SKILL.md`), MCP servers, and future container runners (Docker, OrbStack, Colima, Apple Containers).
- Structured application telemetry, durable public activity and local metric rollups. General telemetry export remains planned.

## Directory map

| Path | Purpose |
| --- | --- |
| `AGENTS.md` | Binding repository rules for humans and agents |
| `CHANGES.md` | What v2 changed and why |
| `LICENSE` | Apache License 2.0 for the open core and plugin contracts |
| `docs/` | Product, architecture, data, workflow, security, UI, shell, plugins, and knowledge specifications |
| `docs/CUCKODING-CONTROL.md` | Start-board behavior, controls, reviewed commit chain, implementation checklist and open acceptance gates |
| `docs/DEVELOPMENT.md` | Current pinned toolchain, source/native builds, data upgrades and runtime surfaces |
| `docs/PLAN.md` | Source progress by phase and the remaining MVP acceptance checklist |
| `docs/DOCUMENTATION_AUDIT.md` | Current source audit and dated documentation/verification history |
| `docs/IMPLEMENTATION_READINESS.md` | Historical Phase 0 toolchain and Phase 1 entry evidence |
| `docs/MVP_BOUNDARY_AND_POSITIONING.md` | Launch contract, competitive scan, data defaults, and commercial hypotheses |
| `docs/BETA_RUNBOOK.md` | Safe dogfood protocol, interview guide, knowledge rubric, and beta exit gates |
| `docs/BETA_REPORT.md` | Anonymized run, interview, knowledge, finding, and decision ledger |
| `docs/RELEASE_READINESS.md` | Current support, privacy, recovery, and MVP release decision |
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

## Contributing

1. Read `AGENTS.md`, `docs/PRODUCT.md`, `docs/ARCHITECTURE.md`, `docs/SECURITY.md`, and `docs/EXECUTION_ENVIRONMENTS.md`.
2. Use `docs/PLAN.md` and the current task file to select the next incomplete item. Phase 0 and the walking skeleton are historical foundations, not a fresh-bootstrap checklist.
3. Claim one task, inspect the existing flow and working-tree changes, and apply the repository's Ponytail guidance before editing.
4. Create one worklog entry for every meaningful implementation session.
5. Record architecture changes in `docs/DECISIONS.md` before changing a settled boundary.
6. Treat task acceptance criteria and verification commands as completion gates.
7. Do not mark a phase complete until its checklist in `docs/PLAN.md` passes.

## Repository shell commands

Prefix every repository shell command with `rtk`. This applies to inspection, Git, Mix, tests, formatters, linters, XERJ, and release checks. Use `rtk proxy <command> ...` only when exact unfiltered streaming output is required or an RTK adapter changes command semantics. Record the exception in the task worklog.

The commands stored in `.cuckoding/project.yml` remain the underlying commands, such as `mix test`. Cuckoding validates the underlying command and its policy first; the optional RTK plugin wraps it afterward. See `docs/REFERENCE_CODING.md` before implementing an unfamiliar problem.

## Pack placement

The `.agents/` and `.cuckoding/` directories are at the repository root, matching the execution and configuration contracts. Do not create nested or duplicate copies.

## MVP boundary

The first supported distribution targets macOS on Apple Silicon. The MVP is
single-user and local-first, with host execution and no container isolation.
Provider CLIs can use their configured remote services. Container runners,
remote workers and team collaboration are future extensions. Local completion
produces a reviewable branch; draft PR creation requires an approved host-side
handoff. Merging and release remain explicit human actions.

## Source currency

README and current-flow documentation were checked against the task 1049 working
tree on **2026-09-25**; see the [documentation audit](docs/DOCUMENTATION_AUDIT.md).
External integration notes retain their original source dates. Revalidate CLI
flags, authorization behavior, pricing and packaging before changing a pin or
claiming provider/release acceptance. Historical test counts, builds and PIDs
do not establish the currently installed or running revision.
