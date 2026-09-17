# Agent Runtime Adapters

## Purpose

Agent runtimes differ in authentication, model selection, structured output, permission systems, session continuation, usage reporting, MCP support, skill/instruction file conventions, and cancellation. Adapters isolate those differences from workflow logic. All runtimes run on the host as child processes of the control plane.

## Required behaviour

- `probe/1`: installation path, version, authentication status, health.
- `capabilities/1`: structured output, native resume, cancellation, usage, MCP, permission modes, model discovery, instruction-file conventions, skill directory support.
- `start/2`: launch a stage with a typed request and capability grant; return process identity and session ID.
- `send/3`: send a bounded follow-up or finding package when supported.
- `pause/2`: request a safe checkpoint.
- `resume/3`: resume a native session or start from a continuation package.
- `cancel/2`: terminate cleanly, then escalate within policy.
- `inspect/2`: current public state and identifiers.
- `decode_event/2`: convert provider output into normalized events.
- `collect_usage/2`: provider-reported facts plus source and confidence.
- `render_config/2`: generate the per-run instruction/permission/MCP/skill files inside the run's `agent/` folder from the grant, knowledge injection set, and enabled plugins; return the effective grant for audit.

An adapter records the configured grant and the runtime-reported grant separately. It is unavailable when the runtime starts undeclared global plugins/MCP servers, exposes unrelated configuration, or writes session state outside documented provider paths that the user has accepted. A deny rule for tool invocation does not prove that the corresponding server process was never started.

`Cuckoding.Adapters.AgentAdapter` is the workflow-facing contract. Its shared types keep requested and observed model identity separate, attach source and confidence to usage, classify adapter errors for retry decisions, and mark every normalized provider event as untrusted. Recording an observed session updates the full effective grant and appends a same-transaction audit event whose public payload contains field names rather than path or policy values. `Cuckoding.Adapters.FakeAdapter` exercises the complete contract without a provider dependency. Its generated fixture configuration is mode `0600`, exists only at `<run_dir>/agent/fake-adapter.json`, rejects a symlinked `agent/` directory, and records restrictions the fake cannot enforce under `unenforced`.

## Stage request envelope

- project, board, task, run, stage, and attempt IDs;
- role instructions and stage objective;
- trusted specification and input artifact references;
- worktree path, run folder, ports, preview URL;
- allowed tool categories, paths, network class (advisory), budgets;
- knowledge injection set (always-injected index and triggered items) and on-demand retrieval endpoint;
- enabled plugins for the stage (instruction skills, MCP servers, shell filters);
- required output schema;
- correlation ID and idempotency key.

Provider prompts clearly separate trusted system policy, user intent, retrieved knowledge, repository content, and previous-agent artifacts. Repository text, knowledge, and plugin output are untrusted data and cannot grant capabilities.

## Permission mapping

Each adapter documents how the capability grant maps onto the runtime: allowed tools, working directory, permission/approval mode, MCP servers, additional directories. The adapter records the effective grant on the agent session. Where a runtime cannot express a restriction, the adapter reports it as `unenforced` and the run detail shows it.

## Normalized event types

`session.started`, `session.heartbeat`, `session.completed`, `session.failed`, `activity.summary`, `tool.requested`, `tool.started`, `tool.completed`, `tool.denied`, `artifact.created`, `finding.created`, `checkpoint.created`, `usage.reported`, `rate_limited`, `approval.requested`, `error.observed`, `knowledge.cited`.

Events contain public summaries and structured metadata. Do not map hidden reasoning into an event.

## Runtime matrix

Capabilities must be probed at runtime and documented per supported version; this table is an implementation target, not a permanent claim.

| Runtime | Invocation | Auth | Key adapter concerns |
| --- | --- | --- | --- |
| Claude Code | Headless/print mode | User login on the machine | Session continuation, permission modes and allowed tools, hooks, structured output, usage availability, auto-memory directory location (keep run-scoped, never write the user's global memory) |
| Codex | CLI non-interactive | User login | Approval/sandbox modes (the runtime's own macOS sandbox is a plus on the host runner), event stream, session identifiers, usage |
| Cursor Agent | CLI/headless | Cursor account | Non-interactive behavior, model observability, usage detail, cancellation |
| OpenCode | CLI/server | Provider-specific | Provider/model mapping, event normalization, permission boundary |

### Claude Code 2.1.142

The implemented adapter pins `2.1.142`, uses `--bare --print --output-format stream-json`, `dontAsk` plus explicit allow/deny rules, strict run-scoped MCP configuration, run-scoped settings and skills, bounded budget/schema flags, and native `--resume`. It launches only through `LocalProcessRunner`, so cancellation uses the recorded process group. A non-interactive follow-up uses the tracked resume path; `send/3` fails closed instead of launching an untracked second process. Provider events are accepted from the pinned redacted fixture vocabulary, with hidden-reasoning and unknown shapes rejected; public text, tool metadata, and knowledge citations are redacted before becoming normalized events.

The effective grant marks tool allow/deny rules, approval mode, and the explicit plugin set as enforced by Claude Code. Worktree path, network, and resource limits remain `unenforced` at the adapter layer and rely on the host runner/runtime sandbox controls. The adapter never uses bypass-permissions mode.

`--bare` is required to prevent user-global hooks, plugins, MCP servers, auto memory, and instruction discovery. It also intentionally skips OAuth and Keychain authentication. Cuckoding therefore accepts only a host-approved absolute executable `apiKeyHelper` for this mode and does not claim authentication until a separate run-scoped probe succeeds. A machine with only global Claude OAuth login reports `run_scoped_auth_required`; Cuckoding does not expose the user's real home or copy credentials to make that login work. Auto memory and background tasks are disabled independently in the child environment as defense in depth.

## Model identity

Store both `requested_model` and `actual_model`. If the runtime does not disclose the actual model, display `not reported`; never silently copy the requested value.

## Authentication

- Use the runtime's documented user authentication; Cuckoding probes and reports status.
- Never copy credential directories or global runtime configuration into the run folder.
- Scrub environment snapshots and child-process arguments.
- A missing or expired credential blocks only that adapter.

## Sleep, cancellation, and recovery

- After a detected sleep gap, the adapter probes the process (PID plus start identity) and the session; live processes continue, dead ones enter recovery.
- Termination ladder: graceful stop, bounded wait, then `SIGINT`, `SIGTERM`, and `SIGKILL` for every owned descendant process group before the root group. Record every step and verify every observed PID and PGID is gone.
- If native resume is absent, create a size-bounded continuation package containing the task revision, current spec, relevant diff, completed checks, open findings, artifact hashes, and a concise public handoff. Never replay unbounded transcripts.

## Adapter conformance tests

Every adapter must pass: version and authentication probes; start, activity, artifact, and completion contract tests; malformed and adversarial output tests; timeout, cancellation, process-tree cleanup, and restart recovery tests; sleep-gap recovery tests; missing usage and unknown model tests; secret redaction tests; effective-grant recording tests; knowledge injection and citation tests; pause/resume tests when advertised; fixture compatibility tests for every supported runtime version.
