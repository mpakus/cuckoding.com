# AGENTS.md

These rules apply to the entire Cuckoding repository. A more specific `AGENTS.md` may add stricter rules inside a subtree, but it may not weaken security, auditability, or verification requirements defined here.

## Mission

Build a local-first macOS orchestrator that lets developers run multiple isolated agent workflows on their own machine, see live who is doing what, keep runs alive across hours and laptop sleep, recover them after failure, accumulate reviewed project knowledge, and produce reviewable Git branches with trustworthy provenance.

## Required reading

Before changing implementation code, read:

1. `docs/PRODUCT.md`
2. `docs/ARCHITECTURE.md`
3. `docs/DB.md`
4. `docs/FLOW.md`
5. `docs/SECURITY.md`
6. `docs/EXECUTION_ENVIRONMENTS.md`
7. The task file assigned to the work
8. Any relevant skill in `.agents/skills/`

## Non-negotiable boundaries

- The database is the durable source of truth. Never make a GenServer, LiveView process, terminal buffer, or agent session the only owner of workflow state.
- Bind the local web server to loopback only. Require a one-time shell-to-application handshake and a short-lived browser session.
- Agents and repository commands run on the host as supervised child processes in their own process groups, confined to the run's worktree and the paths the policy allows. There is no container isolation in the MVP; never describe the host runner as a sandbox.
- Never pass GitHub or provider credentials to an agent process. Git push and PR creation are host-side application services that run after human approval.
- Never expose the user's home directory, SSH keys, cloud credentials, Keychain, or unrelated repositories through Cuckoding's own configuration, environment, or MCP servers; use the runtime's permission system to constrain the agent and record what was granted.
- An agent may propose changes to `.cuckoding/`, but it may not execute newly modified execution policy in the same run without explicit approval.
- Do not display or persist hidden chain-of-thought. Store public summaries, tool activity, artifacts, decisions, and normalized state transitions.
- Project knowledge stays project-scoped until a human approves publication to the global namespace.
- The application must remain usable when any plugin, any single agent provider, the network, or the machine's sleep/wake cycle interrupts work.

## Engineering rules

- Prefix every repository shell command with `rtk`. Use `rtk proxy <command> ...` only when exact unfiltered streaming output is required or RTK changes semantics, and record that exception in the worklog. Commands stored in product configuration remain unwrapped so policy validates the underlying command before the optional runtime shell filter is applied.
- Before implementing an unfamiliar problem, follow `docs/REFERENCE_CODING.md`: search the project and pinned peer indices, inspect the cited source at `path:line`, verify its license, and record what was adapted and which Cuckoding boundary changes the solution.
- Prefer small, explicit OTP components with supervision and restart semantics.
- Use behaviours at every replaceable boundary: runner, provider adapter, plugin kinds, knowledge backend, metrics collector, VCS host, and secret store.
- Use Git worktrees for concurrent feature isolation and per-run port ranges and process groups for runtime isolation.
- Use leases with TTL and heartbeat for exclusive resources; expired work must be recoverable. Heartbeat gaps caused by system sleep are reconciled, not treated as crashes.
- Persist an append-only event before broadcasting it to LiveView clients.
- Make commands idempotent with a stable command key.
- Store timestamps in UTC and monotonic time for durations; record sleep gaps explicitly.
- Keep provider-specific payloads as redacted JSON only when they are needed for diagnosis; normalize the fields used by product logic.
- Version workflow definitions, policy snapshots, plugin manifests, model price catalogs, and knowledge artifacts.
- Do not estimate a value and label it measured. Plugin-reported savings, inferred provider costs, and retrieval-assisted context reductions must be visibly marked as estimates.
- Knowledge lives as Markdown files the user can read and edit; SQLite holds the index, provenance, and usage records.

## UI rules

- The UI is Phoenix LiveView with Tailwind, served on loopback and opened in the default browser. Avoid adding a second application framework.
- Every long-running action must show state, elapsed time, owner role, runtime, model when known, and a safe control: pause, resume, retry, stop, or inspect.
- Every state change must have an accessible non-drag alternative. Kanban drag-and-drop is an enhancement, not the only control.
- Never use color as the only status signal.
- Destructive and trust-boundary actions require confirmation and an audit event.

## Database and migrations

- SQLite uses WAL mode, foreign keys, busy timeout, and short write transactions.
- Migrations are forward-only in released builds and must be tested against a copy of the prior schema.
- Keep immutable historical facts in event or attempt rows; use projections for current state.
- Money is stored as integer micros in a declared currency. Token counts and bytes are integers.

## Testing gates

Before completing a task, run the relevant subset of:

- Elixir formatter, compiler with warnings treated as errors, unit tests, and static analysis.
- Shell (Rust/Swift) formatter, lints with warnings denied, and shell tests.
- Migration and crash-recovery tests.
- Path-confinement, command-policy, and secret-canary tests.
- Sleep/wake and long-run reconciliation tests.
- Plugin conformance tests for any touched plugin kind.
- LiveView accessibility and end-to-end workflow tests.
- Packaging smoke test on the supported clean macOS target.

Record the exact commands and results in `worklog/`.

## Task protocol

1. Claim exactly one task file and add a worklog entry.
2. Restate the task's acceptance criteria before implementation.
3. Inspect existing code and dirty worktree state before editing.
4. Make the smallest coherent change that satisfies the task.
5. Add tests and operational telemetry with the feature.
6. Update affected docs and decisions in the same change.
7. Run verification, record evidence, and check every completed item honestly.
8. Leave an explicit handoff if work is blocked or partial.

## Commit and branch conventions

- Branch: `feature/<task-id>-<short-name>` or `fix/<task-id>-<short-name>`.
- Commit: `<type>(<area>): <imperative summary>`.
- Do not combine unrelated task IDs in one branch.
- Generated files, migrations, and configuration snapshots must be committed when required for reproducibility.

## Use of repository skills

Choose only the skills relevant to the current task. Skills guide execution; task acceptance criteria remain authoritative. In particular:

- Use `local-runner` for worktrees, process groups, ports, confinement, and power handling.
- Use `plugin-system` when adding or changing any connector kind.
- Use `knowledge-compression` for extraction, consolidation, publication, and usage tracking.
- Use `security-review` for any change touching execution, credentials, paths, processes, networking, updates, plugins, or knowledge publication.

## Stop conditions

Stop and request a human decision when:

- a secret or credential appears in logs, artifacts, or knowledge candidates;
- requested access exceeds the current capability grant or the runtime's permission grant;
- a plugin requests host access beyond its manifest;
- the target branch contains conflicting uncommitted user changes;
- a migration risks irreversible data loss;
- provider output cannot be distinguished from a trusted application command;
- publishing knowledge could expose another project, person, or organization.
