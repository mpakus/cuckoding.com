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

## Autonomous role continuity (task 1055)

`BoardControl.Conversations` persists logical execution/controller and task/role
identities on every autonomous stage session. Attempts and accounting remain
separate. A completed session is a native-load candidate only when account,
runtime version, requested and observed model, role configuration, workspace and requested
grant match, and the provider previously negotiated `loadSession`. ACP negotiates
again before loading. If support disappeared, the authorized continuation falls
back before sending any prompt; its saved mode becomes `saved_evidence`.
Other mismatches start fresh with a size-bounded `ContinuationPackage` of current
assignment, public summaries and artifact hashes. No transcripts or hidden
reasoning are copied. Session IDs alone never prove live process ownership.

The plan Reviewer uses its assigned runtime/model in a distinct read-only
conversation; the manual another-model review option is unchanged. Native
continuation and packaged-app evidence for this extension remain separate from
fixture coverage; consult [the worklog](../worklog/2026-09-28-1055-autonomous-board.md).

## ACP communication (task 1054)

All three supported adapters now use `Adapters.ACP.Client`: native Cursor ACP,
and packaged Codex/Claude bridges with pinned policy patches. Authenticated
Codex and Cursor read-only turns pass, and Codex planning produces validated
proposals. An isolated Codex board batch
completed controller, specification, implementation, review and local completion
after an explicit retry; the acceptance repository's main stayed unchanged. The
development bundle was rebuilt, verified and restarted on 2026-09-27. Developer
ID distribution, physical sleep and broader provider acceptance remain separate.
See ADR-031 in
[Decisions](DECISIONS.md) and [bridge build instructions](../agent_bridges/README.md).

`Adapters.ACP.Client` is a supervised ACP v1 client above the existing host
runner. The runner separates protocol stdout from redacted diagnostic stderr.
Starting returns a `starting` session after local process creation, without holding
the run-control lock across provider negotiation. `Adapters.await_session/2` binds
the saved session and process record before initialization. The client negotiates
capabilities, creates or explicitly loads a session, selects an advertised
mode/model (including modern configuration options), and saves the reported
identity before sending a prompt. Configuration notifications cannot widen the
selected mode or silently replace the model.
A durable command reserves each attempt before its first prompt; replacing a
client cannot replay a consumed attempt. Loading history does not create new
activity or usage records. Dead sessions require an explicit recovery decision.

Public message and tool updates use the existing activity/event contexts before
broadcast. Hidden reasoning and raw tool payloads are discarded. Text fragments
are assembled before redaction so split secrets cannot reach public activity.
Protocol frames and final messages are limited to 1 MiB, outstanding requests to
eight, normalized events to 10,000, total protocol output to 64 MiB and diagnostic
artifacts to 4 MiB. Oversized diagnostic lines are omitted. Missing usage stays
unavailable; context-window occupancy is not added to billable token totals.
Selecting a model does not invent an observed model when the agent has not
reported it.

The client advertises no filesystem or terminal services and supplies no ACP
MCP servers. Claude receives only the snapshotted, explicitly configured MCP
servers through its trusted SDK options. Runtime configuration still enforces
the recorded grant.
The pinned Codex and Claude bridges also negotiate AIR `sessionFailure` metadata.
Terminal service/rate failures explicitly permitting retry use the goal's bounded
provider-wait path. Quota/authentication failures remain exceptions; free-form error
titles do not drive recovery and private failure details are not retained.
Permission requests receive a cancelled outcome and require attention;
unsupported client requests cannot start host tools. An ACP completion only
finishes the agent turn: existing schema, review and completion-policy gates
remain authoritative.

Run Stop, including board Stop/Skip, closes durable admission before requesting
ACP cancellation. A stalled handshake can be stopped without waiting for its
provider timeout. Pause suspends owned process groups and retains one bounded
pending negotiation request; resume continues that session without replaying the
prompt. Protocol admission never blocks the client's cancellation mailbox.
Late observations retain committed paused/cancelled state. Recovery requires the
same live protocol owner, saved session, and verified process identity; persisted
provider identifiers alone cannot establish a resumable live transport. Startup
and wake reconciliation block a surviving ACP process whose protocol owner is
missing, preserve terminal sessions, and never create a replacement attempt.

Cancellation waits for acknowledgement or bounded escalation and verified
process cleanup. A paused process is terminated without resuming its work.
An idle server that ignores stdin closure is terminated through
the existing owned process-group ladder. A completed turn can then succeed while
retaining the real process exit status. Authenticated read-only turns using
Codex 0.146.0 and Cursor 2026.09.15-d2fe57e returned exact structured results,
persisted observed models/session identity and public tool activity, and left
clean worktrees with verified process cleanup. Codex also completed the product
planning path. Cursor proposal review requested shell approval and halted with
its proposal history preserved; bounded, redacted public tool titles identify
such requests without storing raw tool arguments.

Claude bridge/native session creation and mode/model selection pass without a
provider prompt; no approved Claude authentication helper was available for an
authenticated turn. Fixtures cover restart/wake ownership and cancellation.
An isolated Codex board batch completed after an explicit retry, retaining the
failed attempt and reviewed README commit. Physical sleep, broader provider
workflows and packaged-app acceptance remain separate evidence in the task worklog.

## Stage request envelope

- project, board, task, run, stage, and attempt IDs;
- role instructions and stage objective;
- trusted specification and input artifact references;
- worktree path, run folder, ports, preview URL;
- allowed tool categories, paths, network class (advisory), budgets;
- knowledge injection set (always-injected index and triggered items) and on-demand retrieval endpoint;
- every injected item includes its immutable ID/version citation and an
  explicit untrusted-evidence marker; the orchestrator records usage only
  after the adapter successfully renders/starts from its run-owned config;
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
| Claude Code | Packaged ACP bridge → native SDK stream | Approved run-scoped API-key helper | Session continuation, permission modes and allowed tools, hooks, structured output, usage availability, auto-memory directory location (keep run-scoped, never write the user's global memory) |
| Codex | Packaged ACP bridge → native app-server stdio | App-owned file login | Approval/sandbox modes (the runtime's own macOS sandbox is a plus on the host runner), event stream, session identifiers, usage |
| Cursor Agent | Native ACP over stdio | Cursor account | Permission/configuration preservation, model observability, usage detail, cancellation |
| OpenCode | CLI/server | Provider-specific | Provider/model mapping, event normalization, permission boundary |

### Claude Code 2.1.142

The adapter pins native CLI `2.1.142` and packages `claude-agent-acp` as
`0.81.2+cuckoding.1`. Its SDK subprocess retains `--bare`, explicit allow/deny
rules, strict MCP configuration, run-owned settings/skills, and native budget
and JSON-schema enforcement. Only `dontAsk` and `plan` modes are advertised.
The bridge reads one immutable settings snapshot instead of discovering project
or personal settings; it does not inject managed environment variables, while
native Claude policy still applies. A loaded session uses the current saved
grant. Native structured results become a separate ACP public message before the
turn completes. `send/3` still refuses untracked follow-ups, and a lost process
requires explicit recovery into a new attempt. Legacy event decoders remain for
historical evidence.

The effective grant marks tool allow/deny rules, approval mode, and the explicit plugin set as enforced by Claude Code. Worktree path, network, and resource limits remain `unenforced` at the adapter layer and rely on the host runner/runtime sandbox controls. The adapter never uses bypass-permissions mode.

`--bare` is required to prevent user-global hooks, plugins, MCP servers, auto memory, and instruction discovery. It also intentionally skips OAuth and Keychain authentication. Cuckoding therefore accepts only a host-approved absolute executable `apiKeyHelper` for this mode and does not claim authentication until a separate run-scoped probe succeeds. A machine with only global Claude OAuth login reports `run_scoped_auth_required`; Cuckoding does not expose the user's real home or copy credentials to make that login work. Auto memory and background tasks are disabled independently in the child environment as defense in depth.

### Codex CLI 0.146.0

The adapter pins native CLI `0.146.0` and packages `codex-acp` as
`1.13.1+cuckoding.2`. The bridge launches the explicitly selected native binary
with `app-server --stdio --strict-config`. Cuckoding sets approval policy Never,
user-owned approval review, true read-only or worktree-write mode, no network or
web search, no extra writable temporary directories, and disabled apps, hooks,
plugins, remote plugins and subagents. The same overrides apply at process and session
setup; patched turn presets cannot weaken them. Native `outputSchema` comes
from the stage's generated schema. Large schema/configuration payloads stay in
run-owned files; instructions reach native thread setup over stdio, avoiding
process argument/environment limits. Reviewed knowledge is supplied as explicit
run instructions, and ACP session loading replaces `codex exec resume`.

This pinned app-server does not accept the legacy CLI's `--ignore-user-config`
or `--ignore-rules` flags. Cuckoding therefore rejects a project `.codex` path or
account-owned rules/hooks or execution configuration before launch. A bounded,
regular account config containing only native absolute-path project trust entries
is accepted unchanged; extra settings and symlinks are rejected. Codex can create
these entries during an authorized turn. Provider-created plugin caches may
remain: both `features.plugins` and `features.remote_plugin`
are explicitly disabled. The bridge omits an upstream diff-path feature flag
unsupported by this pinned native version; it preserves the host feature
overrides. Resolve rejected configuration explicitly before retrying.

The effective grant records the active Codex sandbox, non-interactive approval policy, worktree-only write boundary, network denial, and disabled web search. Codex `0.146.0` cannot express Cuckoding's per-tool allow/deny vocabulary, and the adapter does not add extra writable paths or expose MCP plugins, so those requested fields are recorded under `unenforced` or unavailable. The host command-policy and process-resource boundaries remain independently authoritative. Codex's own sandbox intentionally keeps Git administrative paths read-only; host-side Git services remain responsible for commits and later push/PR operations.

Saved Codex accounts select `cli_auth_credentials_store = "file"`, the
[official app-home credential-store setting](https://learn.chatgpt.com/docs/auth).
Login, status, model discovery, launch and logout use one private home below
`~/Library/Application Support/Cuckoding/provider-accounts/`. The provider
stores refreshable credentials in `CODEX_HOME/auth.json`; Cuckoding rejects
symlinked or group-readable files without reading their contents. Run-specific
instructions, output schema and permission overrides remain separate. The
previous keyring selection passed a personal-shell status check but failed in
the isolated run `HOME`; it cannot be reused without a new sign-in. Authenticated
cross-project execution remains a real-provider gate. Cuckoding does not copy
`auth.json`, pass an API key, expose the real home, or bypass a failed probe.
Legacy snapshots without an account reference retain provider-owned file login
in their run home.

Historical Codex JSONL normalization still accepts the fixed stdin prelude and
known Rust diagnostic lines, rejects hidden reasoning, and validates structured
results. New work uses ACP protocol stdout separately from diagnostic stderr;
workflow results no longer depend on parsing a process log. Authentication and
model-discovery probes still use the pinned native CLI. Host schema validation
remains mandatory before a proposal, review or controller decision takes effect.

### Cursor Agent 2026.09.15-d2fe57e

The Cursor adapter uses native ACP over stdio, the runtime sandbox with network denied, explicitly negotiated session loading, provider token usage, and the host runner's process-forest cancellation. Saved agents use an owner-only app-owned `HOME`; `CURSOR_CONFIG_DIR` and `CLAUDE_CONFIG_DIR` remain below `<run_dir>/agent/cursor`. Login, probe, launch, and logout set the pinned CLI's native `AGENT_CLI_CREDENTIAL_STORE=file`, which keeps the refreshable login at `<account-home>/.cursor/auth.json` with provider-managed `0600` permissions. Cuckoding never reads, copies, displays, or injects that file and never falls back to the user's global Cursor login.

Cursor automatically discovers MCP configuration, so a tool permission deny is insufficient. Cuckoding writes and verifies an empty account-owned MCP file, writes run-owned task configuration, does not pass `--approve-mcps`, rejects enabled Cuckoding plugins for this adapter, refuses repositories containing project Cursor CLI, sandbox, MCP, or plugin overrides, and refuses plugin directories created inside the isolated login profile. The effective grant records the runtime sandbox, worktree path, network deny, and disabled MCP/plugins separately from advisory host resource limits. The native CLI resolves the saved `--model` alias (for example `grok-4.7-high`) into an advertised canonical ACP ID. Cuckoding retains the requested alias, records the reported ID including its effort, and locks that ID for subsequent configuration checks. An unknown CLI alias fails before a prompt. Authenticated read-only output and cleanup passed; permission-requiring review stopped safely. Broader workflow acceptance remains separate.

### OpenCode stable stub

The installed OpenCode `1.18.21` application is a desktop app, not evidence of the documented OpenCode CLI. No `opencode` executable is on `PATH`, so the OpenCode stub reports `cli_not_installed`, exposes no adapter capabilities, and rejects every operational callback. If a CLI is later installed, the stub can report its version but remains unavailable as `runtime_isolation_unverified` until pure mode, run-scoped config/state, authentication, permissions, events, cancellation, and recovery pass the adapter conformance suite.

OpenCode remains non-selectable for execution. Project setup may nevertheless
save an OpenCode connection so roles can be configured before support lands;
installation or desktop-app detection cannot silently imply production support.

Custom Agent is the same honest setup boundary without an execution adapter:
project configuration stores its reviewed absolute executable path, while the
UI states that runs remain blocked until a concrete `AgentAdapter` implementation
and conformance evidence exist. Cuckoding does not guess argv, permissions,
authentication, event, recovery, or usage protocols for an arbitrary binary.

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
