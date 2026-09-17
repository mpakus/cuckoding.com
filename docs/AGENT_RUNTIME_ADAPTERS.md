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

## Model identity

Store both `requested_model` and `actual_model`. If the runtime does not disclose the actual model, display `not reported`; never silently copy the requested value.

## Authentication

- Use the runtime's documented user authentication; Cuckoding probes and reports status.
- Never copy credential directories or global runtime configuration into the run folder.
- Scrub environment snapshots and child-process arguments.
- A missing or expired credential blocks only that adapter.

## Sleep, cancellation, and recovery

- After a detected sleep gap, the adapter probes the process (PID plus start identity) and the session; live processes continue, dead ones enter recovery.
- Termination ladder: graceful stop, bounded wait, process-group `SIGTERM`, then `SIGKILL` if policy permits. Record every step.
- If native resume is absent, create a continuation package containing the task revision, current spec, relevant diff, completed checks, open findings, artifact hashes, and a concise public handoff. Never replay unbounded transcripts.

## Adapter conformance tests

Every adapter must pass: version and authentication probes; start, activity, artifact, and completion contract tests; malformed and adversarial output tests; timeout, cancellation, process-tree cleanup, and restart recovery tests; sleep-gap recovery tests; missing usage and unknown model tests; secret redaction tests; effective-grant recording tests; knowledge injection and citation tests; pause/resume tests when advertised; fixture compatibility tests for every supported runtime version.
