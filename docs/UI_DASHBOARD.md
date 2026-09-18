# Visual Dashboard and Interaction Model

## Design goal

The dashboard must answer immediately:

1. What is running, and which role, runtime, and model owns each action?
2. What progress or evidence has been produced?
3. What is each run costing and consuming, and did the machine sleep in the middle?
4. What knowledge has the project accumulated, and where is it being used?
5. What can the user safely do next?

The UI shows normalized public activity, not private chain-of-thought.

## Information architecture

### Agent Floor (default screen)

A live view of who is doing what.

| Area | Content |
| --- | --- |
| Capacity bar | Active/queued/hibernated runs, CPU, memory, cost today, sleep-prevention status, budget warnings |
| Role lanes | One lane per role (spec writer, implementer, reviewer, release). Each lane holds cards for active agent sessions: runtime and actual model badge, project/board/task, current public action, elapsed active time, budget used, last heartbeat |
| Handoff arrows | Live transitions between lanes when a stage passes or bounces back, with the finding count |
| Attention | Blocked approvals, crashed agents, policy flags, budget exhaustion, degraded plugins, post-sleep reconciliation results |
| Controls | Pause board, hibernate run, retry stage, stop run, inspect evidence, open preview URL, open worktree |

Lanes can be grouped by role (default), by runtime, or by project.

The Phase 6 MVP implements this surface at `/agents` from durable agent-session,
attempt, run, task, board, and project records. It caps the projection at 100
cards, keeps current resource, cost, activity, attention, and handoff context on
each card, and provides native links to the run and agent inspectors. PubSub
hints are coalesced into one refresh per 250 milliseconds. A semantic table
contains the same 100-session projection. Mutating lifecycle controls are not
shown unless the application can supply their live ownership handles; inspect
remains the safe control for every recorded session.

### Project workspace

- Project status, repository folder, base branch, configuration revision, runner (host, with limitation notice), plugins in use, tool health.
- Tabs: boards, runs, knowledge, metrics, settings, audit history.
- Aggregate costs and resources filtered by board, runtime, model, role, stage, and date.

### Board view

Each board has its own Kanban, workflow template, assignments, budgets, and concurrency settings. Columns represent workflow stages; the state machine remains authoritative.

Cards show title, priority, dependencies, current role, runtime/model badge, attempt count, elapsed time, budget consumption, blocking reason, and a knowledge indicator (number of items injected in the current stage). Drag-and-drop is allowed only for transitions the state machine permits, with equivalent keyboard and menu actions.

The Phase 5 MVP board currently renders durable task lifecycle states as semantic sections and shows title, priority, waiting reason, and an honest `Knowledge: 0 linked` indicator until Phase 7 supplies usage records. Filters live in the URL so reload and browser history preserve them. Each permitted move has a labeled native select and submit button; drag-and-drop exposes the same server-authorized targets, applies only an optimistic DOM move, and then reconciles from the durable command result. Accepted moves are announced through a polite status region and rejected moves through an alert with the reason. Task title, description, and priority are editable only while the task is Draft or Ready, with each edit recorded as a public event before its projection changes.

### Run detail

- Stage timeline with attempts, sleep gaps, and handoffs.
- Live public activity stream with tool category and target, redacted command summary, duration.
- Preview URL with health, worktree path, ports.
- Diff summary, commits, artifacts, tests, findings, approvals.
- Token and cost breakdown with source/confidence; active vs wall time.
- CPU, memory, process count charts.
- Knowledge panel: items injected, retrieved, cited; candidates extracted from this run.
- Plugins active for each stage and their labeled contribution (for example "RTK: ≈ 41% shell output reduction, estimated").
- Pause, resume, hibernate, retry, stop controls governed by current state.

The Phase 6 MVP route `/runs/:id` renders the durable timeline, public activity,
preview state, direct regular-file artifacts, findings, usage and cost
provenance, measured resource history, captured plugin keys, and labeled plugin
optimization claims. The knowledge panel is an explicit Phase 7 placeholder.
Resource history uses native progress elements plus a complete table; periodic
metric refreshes run every five seconds and committed activity hints are
coalesced separately.

### Agent inspector

Role and granted permissions (as configured on the runtime), adapter and runtime version, requested and observed model, session identifiers with redaction, current stage, last heartbeat, process group and lease, usage, cost, tool activity, errors, resume capability.

The Phase 6 MVP route `/agents/:id` shows only public durable identifiers and
grant keys, never grant values or provider payloads. It attributes process
records, resource samples, usage, and public activity to the selected session.

### Knowledge Growth

Per project and global:

- Items over time by kind and status (candidate, project, global, superseded, revoked), as a stacked area chart.
- Consolidation history: jobs, merges, contradictions resolved, index size.
- Coverage: which areas of the repository have facts/recipes, which do not (by path prefix declared in `project.yml`).
- Review queue with evidence preview and one-click accept/reject/supersede.

### Knowledge Lineage and Usage

- A lineage graph: evidence (runs/artifacts) → candidate → item → versions → runs where injected/retrieved/cited → outcome (accepted, corrected, contradicted). Rendered as a left-to-right flow with counts on edges; click any node to open it.
- Usage table: item, times injected, times cited, acceptance rate, last used, contradiction count, current rank.
- "Unused" and "contradicted" lists as candidates for expiry.
- Skills view: published skills, versions, which workflows enable them, usage and outcome per version.

The Phase 7 review surface at `/knowledge` renders a bounded durable candidate
queue, redaction/evidence disclosure, labeled native review and approval
forms, and an append-only publication history table. Global publication is not
offered until its candidate-specific approval is recorded. Revocation and
rollback are separate approval requests, and every dynamic result is announced
through a polite status region or an error alert. Growth charts, lineage, and
usage remain task 0706.

## Real-time update model

1. Workers persist normalized events.
2. Phoenix PubSub broadcasts the committed sequence number.
3. LiveViews fetch or apply events in order.
4. Reconnect requests events after the last acknowledged sequence.
5. High-frequency metrics use bounded sampling and aggregated chart updates rather than one DOM event per sample.

The UI displays a stale indicator if no heartbeat arrives within the configured interval and a "reconciling after sleep" indicator after a detected gap. A disconnected browser never changes workflow state by inference.

The Phase 6 activity component uses the append-only event stream as its table alternative. PubSub carries only a committed stream ID and sequence hint; the LiveView fetches all later rows, deduplicates them by durable event ID, and caps the rendered recent list. Reload/reconnect uses the same `after_sequence` query. Sleep-gap milliseconds are rendered as explicit timeline text, and stale/reconciling labels remain informational rather than changing workflow state.

## Visual status language

| Status | Shape/icon cue | Typical color cue | Meaning |
| --- | --- | --- | --- |
| Running | Spinner/pulse | Blue | Work is executing |
| Waiting | Clock | Amber | Approval, dependency, rate, or budget wait |
| Paused | Pause icon | Neutral | Runtime retained where possible |
| Hibernated | Snowflake | Neutral | Compute released; state preserved |
| Reconciling | Sync arrows | Neutral | Post-restart or post-sleep reconciliation |
| Blocked | Stop sign | Orange | User action required |
| Failed | Error mark | Red | Attempt ended unsuccessfully |
| Passed | Check | Green | Gate or stage completed |

Text labels and icons are mandatory; color is never the sole signal.

## Command feedback

Every user command returns one of: accepted, already applied, rejected by state, rejected by policy, or failed. Long-running commands show progress and can be inspected. Optimistic UI may reorder cards visually but must reconcile with committed state and explain rejections.

## Accessibility and performance

- WCAG 2.2 AA for contrast, focus, keyboard operation, labels, and reduced motion.
- Table/list alternative for every visual board and graph, including the lineage graph.
- Virtualize long event lists and progressively load artifacts.
- Server-side aggregation for charts.
- Useful at 100 historical cards, 10 live agent sessions, and 5,000 knowledge items.
- Preserve filters and selected board across restarts.

## Sensitive information

- Mask secrets before persistence and before broadcast.
- Collapse raw command output by default and warn before displaying potentially sensitive data.
- Show repository paths relative to the project root unless the user requests absolute diagnostics.
- Exported dashboards include the redaction policy version and metric provenance.
