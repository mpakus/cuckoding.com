# Visual Dashboard and Interaction Model

## Design goal

The dashboard must answer immediately:

1. Which projects have I added, and which need attention?
2. Is Cuckoding healthy, and what CPU, memory, process, and port capacity is active?
3. What is running, and which project, board, task, role, runtime, and model owns each action?
4. What progress or evidence has been produced?
5. What can I safely do next?

The UI shows normalized public activity, not private chain-of-thought.

### Illustrated pearl visual system

The application adapts the supplied pale futuristic reference: cool ivory
surfaces, mist-blue atmosphere, violet accents, rounded floating panels, fine
line icons, and softly rendered illustrations. The reference's small, faint
labels are adapted to readable application text; its sample percentages,
motivational copy, and habit-tracking features are not product requirements.

| Element | Application treatment |
| --- | --- |
| Canvas | Cool pearl `#edeef5`, with a subtle lavender wash |
| Panels | White to near-white, 20–28 px corners, restrained layered shadows |
| Accent | Violet `#6845d9`; darker `#5634bd` for links and focus |
| Text | Ink `#282535`, secondary `#625f76`; system-installed Avenir/Segoe UI sans stack |
| Navigation | Desktop rail; wrapping labeled navigation at narrow widths; active underline plus color |
| Illustration | Original pearl robot/portal banner and violet knowledge crystal; decorative empty alt text |
| Data | Existing durable counts and charts; no invented progress, activity, or measurement |

The home banner has the existing **Add project** action and a compact live
summary of active agents, registered projects, pending approvals, and health.
Shared Tailwind tokens and surface styles carry through settings, boards, run
inspectors, and knowledge screens. Warning/error colors retain their meaning.
Artwork is locally served WebP (approximately 110 KiB total), with explicit
dimensions; no remote fonts, new UI library, or animation dependency is needed.
Only short hover color/shadow transitions run under `prefers-reduced-motion:
no-preference`. Navigation, forms, table alternatives, confirmations, and the
skip link retain native keyboard paths.

Artwork files: `priv/static/assets/images/workspace-portal.webp` and
`priv/static/assets/images/knowledge-crystal.webp`. Generation prompts and
verification evidence are recorded in the [task 1034 worklog](../worklog/2026-09-24-1034-pearl-workspace.md).

### Public GitHub Pages site and illustration modes

`github.page/` is a separate static HTML/CSS/JavaScript surface. Its matching
pearl style does not change the LiveView application or add an app theme switch.
The site uses pearl `#f0f0f6`, paper `#fafafe`, ink `#252432`, secondary text
`#626176`, violet `#6744dc`, dark links/focus `#5232ba`, rounded panels and system
fonts. The hero, workflow and knowledge panels use locally served original WebP
art with intrinsic dimensions; later illustrations load lazily.

The shared brand mark is a C-shaped sperm cell: an oval head and tapered curved
tail, violet on a pearl tile. `desktop/icon.svg` is the editable source;
`desktop/export_icons.rb` exports the website/app SVG copies, browser ICOs,
macOS PNG/ICNS and monochrome tray mask. Header/footer/sidebar marks accompany
the readable product name and use empty alt text to avoid duplicate naming.
Brand icons stay identical in Classic and Irony illustration modes.

| Mode | Assets under `github.page/assets/` | Intended scene |
| --- | --- | --- |
| Classic | `pearl-crew.webp`, `pearl-path.webp`, `pearl-knowledge.webp` | Robots collaborate, follow a deliberate path and maintain a knowledge archive |
| Irony (default) | `irony-crew.webp`, `irony-path.webp`, `irony-knowledge.webp` | Robot managers relax while humans serve coffee, carry their manager and power the archive |

Irony is office satire about humans doing the work for their automated bosses.
It changes artwork and art captions, not product capabilities or release claims.
The native **Illustration mode** radio group has labeled 44 px targets, visible
keyboard focus and a polite status region. It switches all three images and
their alt text plus six captions/labels. Decorative hero art keeps empty alt
text; informative scenes have mode-specific descriptions. The original Classic
assets remain unchanged.

The browser preference key is `cuckoding-illustration-mode`. Only a saved
`classic` value overrides Irony; missing, invalid or inaccessible storage uses
Irony. Storage failure still allows switching within the page. Without
JavaScript, Irony remains visible and the unavailable switch stays hidden.
Static markup, hero preload and social preview all start with Irony.

Concept/satirical art and the illustrative workspace board are labeled as such;
they are not screenshots or measured activity. Native scroll reveals and
decorative parallax respect reduced motion, including a preference change while
the page is open. Each three-image set stays below 400,000 bytes. Prompts,
hashes and rendered checks are in the [1035 design](../worklog/2026-09-24-1035-pearl-pages.md)
and [1036 mode](../worklog/2026-09-24-1036-pages-irony-mode.md) worklogs. Source
checks are in [TESTING.md](TESTING.md); main integration alone does not establish
a successful Pages deployment.

The public copy follows [PRODUCT.md](PRODUCT.md): project setup, reusable agents,
prompt/Markdown planning, another model's proposal review, the default
Speculator → Implementor → Reviewer correction loop, and completion. Feature
panels explain parallel work, individual/workspace controls, supported custom
roles and permissions, evidence, labeled metrics and optional connectors.
Keep manual completion as the default and automatic local completion as an
explicit start-time choice; remote handoff still needs separate approval.
“Available now” describes implemented source, with simulated-agent checks and
pending native/real-provider testing stated separately from public release.
The product specification and release evidence remain linked from the status
panel. See the [1039 copy worklog](../worklog/2026-09-24-1039-pages-product-copy.md).

### Saved agents and provider sign-in

In **Agents**, the wizard follows **Name and runtime → Authorization → Model**.
Authorization suggests an installed executable and offers **Find automatically**
plus an editable absolute path. A failed search preserves manual input; saving
locks that step until **Edit agent**. Discovery can find Codex Desktop's bundled
CLI but does not reuse its sign-in or establish supported-version compatibility.
The final step selects runtime default, a provider-reported model or a validated
custom model ID. See [AGENT_AUTHORIZATION_FLOW.md](AGENT_AUTHORIZATION_FLOW.md)
for search locations and compatibility limits.

New Codex/Cursor agents reuse a compatible saved provider
sign-in by default. A separate sign-in is an explicit choice, not a consequence
of giving an agent another name, model or role. Shared agents link to the original
sign-in controls instead of duplicating login commands. Model suggestions do not
guarantee account entitlement. Roles remain project/board assignments; model
changes affect future configuration snapshots, not existing runs.

## Information architecture

### Home dashboard (default screen)

The `/` route is the project-first entry point. Its order is Projects, Recent
activity, Operations, then Application and resources, followed by attention and
usage evidence. It contains:

| Area | Content |
| --- | --- |
| Projects | Every registered project with repository identity, base branch, board and delivery-task counts, active agents, attention, and task counts by state (including Blocked and Completed) |
| Primary action | **Add project** opens the setup wizard; existing project actions remain on each project, not in a global bootstrap form |
| Application status | Control-plane health, version, and dependency status |
| Resource snapshot | Active agents, measured memory, owned process count, and measured open ports; missing samples are unavailable, not zero |
| Active work | Current agent project/task, role, runtime, model, state, stage/session age, and safe inspect links |
| Attention | Approvals, blocked tasks, failed runtimes, policy changes, budgets, and degraded plugins |

Recent activity groups the latest 20 committed public events into agent/process,
workflow, and system categories. Native meter bars and a count table show the
same bounded data; category buttons filter a collapsible event log. An active
agent list links to run evidence. PubSub hints refresh the activity log after
commit, and a five-second durable reload updates operations, health, and
measured resources. The chart is a mix of recent events, not an event rate or
historical total; an old last event is labeled stale.

The separate live agent chart shows 12 UTC minute buckets for currently active
agent sessions with at least one measured owned-process sample. It re-queries
durable samples every five seconds, uses gaps for unmeasured minutes, and has a
minute-by-minute table alternative. It is not a count of every active agent in
past minutes; when no current session has samples, it says so rather than
inventing a trend. Project state counts come from delivery task projections
across each project's boards. Common states are always visible; uncommon
paused, hibernated, cancelled, and archived states appear when occupied.

Operations is a table of the latest 50 runs, including queued runs without an
agent session. State, project, and task/board/project search filters are local
to the loaded rows. Every row keeps Inspect run and Task links; filtering
never changes workflow state. Application shows health and each dependency;
Resources shows active agent count and latest measured memory, process, and
port totals. Missing samples are labeled unavailable rather than zero.

The home dashboard never asks for project, runtime, task, and release details in
one form. Empty state explains the project → board → task sequence and offers
one **Add project** action.

The shared header links to **Projects**, **Agents**, **Agent activity**, and **Knowledge**.
Dashboard shortcuts jump to projects, activity, operations, and approvals. Creation age
is labeled **Created**, not elapsed execution time. Long paths wrap on narrow
screens; activity tables scroll horizontally without squeezing their headings.

### Project setup wizard

Adding a project is a keyboard-operable wizard:

1. **Project** — name and optional description.
2. **Repository** — select a folder with the system chooser and choose a base
   branch. Empty folders, freshly initialized Git repositories, and existing
   projects are accepted. A dirty existing repository may be registered but
   must be clean before run preparation.
3. **Review** — show repository, branch, pending Git action, runner limitations,
   and the non-executing registration boundary before confirmation.

Step changes announce progress. Back retains edits within the open wizard;
these edits are not a persisted draft and are lost if the page is closed.

Completing this wizard registers only the project and its initial trusted
configuration, then redirects to the project settings page. That page adds,
saves, updates, or removes multiple agent connections; edits or adds roles; and assigns
one connection to every role. Saving appends a configuration version. Board
creation and task creation remain separate follow-up actions, and active boards
and runs keep their original snapshots.

The local Phoenix service invokes the macOS folder chooser; no browser upload
or menubar-only bridge is required. Inspection does not modify the folder.
Final review requires explicit consent before initializing Git or creating the
first commit from existing contents when the repository has no revision.

### Project agents and roles

`/settings/agents` manages machine-wide agents independently of projects, with
add/edit, copyable sign-in commands, async checks and live status. The page
explains that an agent's app-owned profile/history is shared across projects.
`/projects/:id/edit` contains a saved-agent picker and the
project's connections and role assignments. **Use in this project** adds a
connection to the form; **Save agent** or **Save agents and roles** persists it.
Each agent can be saved independently; the complete configuration requires an
assignment for every role. Removing a project connection does not delete its
global account or log it out.

Section shortcuts lead to connections, roles, and boards. Saved agents are a
native disclosure, initially open when no project connections exist. The page
distinguishes saved settings from local edits. Board creation refuses unsaved
configuration, so its snapshot cannot silently use older role assignments.
Save controls show pending feedback; removing a connection asks for confirmation.

Codex and Cursor offer saved-account sign-in commands and **Check sign-in**;
Claude Code uses a reviewed helper. OpenCode
and Custom Agent are setup-only. Complete commands use read-only fields with
adjacent copy buttons. Account status is the last observation, not proof that
a new run can authenticate; every start probes its selected account. See [testing](TESTING.md).
For connected accounts, the sign-in command is hidden behind **Re-authorize
agent**; green status always includes the word **Connected**. A legacy queued
run with no saved-agent ID points to **Assign agents to board** instead of
offering per-role selectors. Run-local sign-in commands are omitted.

Save assignments before creating a board. Existing boards retain their copied
settings, including legacy connections without saved-account IDs. The explicit
**Assign agents to board** action applies current project roles to future runs
and adds audited bindings to compatible queued runs without changing tasks or
workflow snapshots. It is not a general workflow editor.

### Agent Floor

A live view of who is doing what.

| Area | Content |
| --- | --- |
| Capacity bar | Active/queued/hibernated runs, CPU, memory, cost today, sleep-prevention status, budget warnings |
| Role lanes | One lane per role (spec writer, implementer, reviewer, release). Each lane holds cards for active agent sessions: runtime and actual model badge, project/board/task, current public action, elapsed active time, budget used, last heartbeat |
| Handoff arrows | Live transitions between lanes when a stage passes or bounces back, with the finding count |
| Attention | Blocked approvals, crashed agents, policy flags, budget exhaustion, degraded plugins, post-sleep reconciliation results |
| Controls | Pause board, hibernate run, retry stage, stop run, inspect evidence, open preview URL, open worktree |

Lanes can be grouped by role (default), by runtime, or by project. The home
dashboard links here for the complete global operations view.

The Phase 6 MVP implements this surface at `/agents` from durable agent-session,
attempt, run, task, board, and project records. It caps the projection at 100
cards, keeps current resource, cost, activity, attention, and handoff context on
each card, and provides native links to the run and agent inspectors. PubSub
hints are coalesced into one refresh per 250 milliseconds. A semantic table
contains the same 100-session projection. Mutating lifecycle controls are not
shown unless the application can supply their live ownership handles; inspect
remains the safe control for every recorded session.

### Project workspace

Current entry point: `/projects/:id/edit`, with project settings, boards, and
**Create board**. The tabbed workspace and aggregate filters below remain design
targets, not additional shipped routes:

- Project status, repository folder, base branch, configuration revision, runner (host, with limitation notice), plugins in use, tool health.
- Tabs: boards, runs, knowledge, metrics, settings, audit history.
- Aggregate costs and resources filtered by board, runtime, model, role, stage, and date.
- **Create board** is the primary action when a project has no boards; **Add task** belongs to a board, never project setup.

The Phase 8 Settings → Plugins route `/settings/plugins` exposes the durable
registry without color-only status. Each entry names its health and last error,
requested permissions, source, and manifest digest. Native forms provide the
non-drag approval path for enabling or disabling a scope, require a reason and
confirmation, and label the exact network approval class. The page also states
the host runner's advisory network limitation.

### Board view

Each board has its own Kanban and snapshotted workflow and assignments. Current
board creation accepts name, description, and concurrency; workflow selection,
budget editing, and board-assignment editing are not exposed there. Kanban
columns represent task lifecycle states, not Specifications/Coding/Review stages.

New default workflows use Speculator → Implementor → Reviewer; both correction
labels return through Speculator within the bounded loop. Explicit custom roles
run after Speculator or Implementor with snapshotted grants and reports. Older
runs retain their definition. A passing Review follows the recorded manual or
automatic-local completion choice; remote release always requires its separate
approval. Local completion preserves the branch, worktree and evidence.

The fuller card design also calls for dependency lists, attempt/budget details
and knowledge usage; these remain available through inspectors where supported,
not invented per-card measurements. Drag-and-drop is allowed only for transitions
the state machine permits, with equivalent native form actions.

The board shows title, priority, waiting reason and links to task setup/current
run. Active cards also show current stage, snapshotted role name, runtime,
observed model (or explicitly requested model), and stage elapsed time including
pauses. Parallel tasks retain independent progress. The elapsed display refreshes
every five seconds; committed events refresh stage/state from SQLite. It does
not yet show per-card knowledge usage. Draft, Ready,
Running, Waiting, and Done are visible by default, plus any occupied uncommon
state; **Show all states** exposes all lifecycle columns. A state filter shows
that column only. Committed activity hints trigger a coalesced reload from the
database; the LiveView does not own workflow state.

Automatic card-state moves use a 200 ms native transform animation to show where
the card went. Timer/layout-only updates do not animate. Keyboard-focused cards,
reduced motion and background tabs update immediately; changing motion preference
cancels an active animation. No animation library or perpetual activity effect.

Filters live in the URL so reload and browser history preserve them; **Clear
filters** restores the board. Each permitted move has a labeled native select
and submit button. Drag-and-drop exposes the same server-authorized targets
when their columns are visible and reconciles from the durable command result.
Accepted moves use a polite status region and rejected moves an alert. Task
title, description, and priority are editable only in Draft or Ready, with an
event recorded before projection changes. Task detail gives state-specific next
steps, requires local edits to be saved before marking Ready or preparing a run,
and keeps the description readable after editing is locked. Unsaved indicators
are warnings, not auto-save or a browser-navigation guard.
Task detail also shows the latest redacted Specifications message and a bounded,
expandable timeline of stage transitions, artifacts, failures, and public agent
messages across its runs. Agent messages appear
after the provider process yields its log; durable events then refresh the
LiveView without a browser reload. The complete filtered log stays on the run
page. Agent text is labeled untrusted and is never treated as a user command.

At `/boards/:id`, expand **Add a task** or **Ask an agent to plan tasks**.
These native keyboard-operable disclosures keep the task board in reach;
their initial open defaults come from the server, then browser-owned open state
survives LiveView patches using `JS.ignore_attributes("open")`. Live data inside
them continues to update; periodic refreshes must not collapse a form or steal
focus while the user is typing. Other workspace disclosures follow the same rule.
New validation alerts explicitly reopen the relevant board form with
`JS.set_attribute`, retaining visible error feedback.
Choose an assigned role and enter a prompt such as “Read docs/ and propose tasks
from docs/TASKS.md.” **Create planning run** shows submit feedback and navigates
to a queued run; it does not silently start the provider or import cards. On
the run page, authenticate and start analysis, inspect progress, then select
validated proposals to import as Draft tasks. No proposal is imported without
review. Ready does not mean automatically scheduled: each Ready card has
**Set up and start**, linking to **Prepare run** on
`/boards/:board_id/tasks/:id`. Preparation creates the branch/worktree but does
not launch an agent. A task with a queued run instead offers **Open prepared run
and start**; authentication and launch are separate run actions. Move selectors
start with **Choose a state**, not a destructive destination.
Blocked and failed delivery tasks expose **Retry with a new run** on task detail;
the failed run links back to this action. Retry preserves the previous run and
opens the newly prepared run. It never silently restarts an agent or overwrites
the prior worktree. If the project repository is dirty, the task remains Ready
and the page explains how to prepare the run after fixing the issue.

### Run detail

Quick links lead to setup (when queued), timeline, live logs, and findings.
Proposals open for waiting reviews and collapse into **Planning results** after
completion. Remaining proposals may still be reviewed and imported. Agent
activity pages distinguish recorded sessions from saved connections and link
back to project settings for connection management.

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

Under **Artifacts**, **Live process logs** follows the selected run-owned log
every second with at most the latest 5,000 lines. Scroll-up preserves the reading
position; **Pause live log** stops viewer updates only, not the agent. Selecting
another log follows its tail. Reconnect reloads from disk; truncation/replacement
is picked up on refresh. **Download full filtered log** streams a snapshot of
the selected file, including earlier output outside the preview.

Both views normalize supported provider events into public summaries and tool
metadata and redact secrets. Hidden reasoning, unsupported/plain output,
malformed entries, and lines over 64 KiB become omission markers; this is not a
raw terminal transcript. Preview reads are additionally bounded to the final
8 MiB, so unusually large lines can yield fewer than 5,000 rows, with a visible
limit notice. The download is streamed without that preview byte cap. Its
loopback-only endpoint requires the same browser authentication as the app
when authentication is enabled, disables caching, and resolves only a validated
artifact ID beneath the run's recorded artifact directory. User-supplied paths,
symlinks (except the fixed macOS `/var` and `/tmp` system aliases), and hardlinked
files are rejected. Raw artifacts remain on disk; they are never served directly.

Queued planning runs show the next authentication/start action before any
agent session exists. Failures show a sanitized cause and recovery guidance;
older runs without retained diagnostics explicitly say so. Planning output
validation failures remain distinct from provider process failures. The home
dashboard includes queued operations; Agent Floor requires a recorded session.
The saved-agent catalog refreshes after its own actions, not through a global
real-time subscription. Do not describe every settings view as auto-updating.

Task detail, run detail, and agent inspector show the same non-color-only host
runner warning: a worktree prevents normal Git overlap but is not filesystem,
network, CPU, or memory isolation. It tells the user to review permission mode,
worktree, protected paths, network class, plugins, opaque secret references,
budget, expiry, and the enforced/unenforced grant split before starting work.

### Agent inspector

Role and granted permissions (as configured on the runtime), adapter and runtime version, requested and observed model, session identifiers with redaction, current stage, last heartbeat, process group and lease, usage, cost, tool activity, errors, resume capability.

The Phase 6 MVP route `/agents/:id` shows only public durable identifiers and
grant keys, never grant values or provider payloads. It attributes process
records, resource samples, usage, and public activity to the selected session.

### Knowledge Growth

Per project and global:

- Items over time by kind and status in a bounded daily trend table.
- Consolidation history: project, state, revision, and index hash.
- Coverage: total, used, project-scoped, and global-scoped items.
- Review-queue coverage by candidate kind and decision, linked to the full review surface.

### Knowledge Lineage and Usage

- A lineage graph: evidence (runs/artifacts) → candidate → item → versions → runs where injected/retrieved/cited → outcome (accepted, corrected, contradicted). Rendered as a left-to-right flow with counts on edges; click any node to open it.
- Usage table: item, times injected/retrieved/cited, acceptance rate, last used, contradiction count, and current retrieval rank.
- "Unused" and "contradicted" lists as candidates for expiry.
- Skills view: published skills, versions, source items, and publication time.

The Phase 7 review surface at `/knowledge` renders a bounded durable candidate
queue, redaction/evidence disclosure, labeled native review and approval
forms, and an append-only publication history table. Global publication is not
offered until its candidate-specific approval is recorded. Revocation and
rollback are separate approval requests, and every dynamic result is announced
through a polite status region or an error alert.

`/knowledge/growth` and `/knowledge/lineage` load bounded server-side
projections. Growth caps its daily groups and consolidation rows. Lineage caps
reviewed chains, run edges, unused/contradicted lists, skills, and usage
summaries. Its left-to-right flow uses linked evidence, candidate, item, run,
and outcome nodes, followed immediately by a semantic table alternative.
Both pages refresh their complete durable snapshot in one LiveView assignment
every ten seconds rather than applying per-row updates.

## Public message boundary

Browser messages never interpolate raw tuples, atoms, changesets, exceptions,
provider output, or third-party plugin errors. Expected failures use reviewed
screen-specific copy that says what happened and the next safe action.
`CuckodingWeb.PublicError` formats only application-owned validation field names
and messages; it caps the displayed errors and never includes submitted values.
Unexpected failures collapse to fixed recovery copy. Run-scoped failures point
to the durable timeline, findings, logs, or release evidence rather than
displaying internal terms. Every dynamic success uses a polite live status
region and every dynamic failure uses an alert. Empty states explain what will
populate the view or name the next available action.

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
