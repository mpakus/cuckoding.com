# Interface contract

**Add folder → Create tasks → Start.** One Arena page becomes its working dashboard;
agent/model/role setup is saved once. Phoenix LiveView, HEEx and Tailwind remain
the stack. [Flow](FLOW.md) owns transitions/authority; [Plan](PLAN.md) tracks delivery.

## Visual structure

A slim sidebar and one or two primary regions: the board and an optional inspector.
A Tabula still shows every column; the region limit is not a card limit. Keep the
black/green, futuristic mouse-friendly TUI: near-black `#050807`, dark-green panels
`#0b110e`, electric-green `#82ff52` focus/actions and off-white readable body text.
Use crisp borders, generous space and monospace labels/logs. No decorative control
room, blinking cursor, terminal emulator, extra framework or analytics clutter.
Motion clarifies changes and respects reduced motion. Status includes text/icons.
Mobile form text is at least 16px; sidebar navigation becomes one scrollable row.

Sidebar: **Tabula Gladiatorum**, **Arenas**, **Agents**, **Team**, **Settings**.
Explain names initially: Arena · project, Tabula · board, Summa Rudis · coordinator,
Secutor · completion review. No competing start screen or separate Agent Floor.

R080c shows a quiet five-step navigation rail: **Agents → Roles → Arena & Tabula
→ Create tasks → Start**. These are destinations, not a second wizard or proof
of execution readiness. Home derives its next action from saved usable model
choices, required role bindings and the latest Arena/board; existing Arenas stay
directly accessible even if a connection needs repair. No navigation launches
providers, adopts a team or changes a board. The ten-minute goal still needs a
timed real-account acceptance run.

Team puts agent/model selectors directly on four role cards; names/instructions
and history remain available on demand. A clean saved form offers **Next: Choose
Arena**; dirty text stays in the current editor. Arena exposes **Board team** in
a shared dialog and a contextual **Review saved team** link when its saved scope
differs. Adoption still previews both teams and requires explicit confirmation.

R080d separates **agent missing** from **agent assigned, model missing** in Start
and links binding problems directly to the affected Team role. Connection errors
retain exact-agent setup links. Inspect and Board team show **Model needed**
without hiding the selected agent. Team lists incomplete required roles while
still allowing draft saves; successful Save preserves the explicit submitted
agent/model pair even when the server has not seen an earlier change event.
Changing an agent in the editor still clears its previous model. The domain
validates each new binding; saving neither chooses a model nor adopts a board team.

## Arena states

| State | Main surface | Primary action |
| --- | --- | --- |
| Add folder | Native chooser, suggested folder name and saved-team summary | Add Arena |
| Empty Arena | Empty default board; brief/source dialog on demand | Create tasks |
| Analyzing | Phase, elapsed time, Speculator/runtime/model, source scope | Cancel |
| Tasks ready | Editable cards, compact team/progress and Start scope | Start |
| Running | Same board with automatic moves and current workers | Pause; Stop available |
| Needs attention | Concrete blocker, what was tried, smallest repair | Resolve / Resume |
| Completed | Reviewed local result, criteria and evidence | Inspect result |

Adding the folder defaults its name and creates the five-column board with its
inherited team. Navigate straight to `/arenas/:id`; registration performs no
content read, Git mutation or agent launch. Do not require another board creation.
Existing Tabula deep links remain usable. Never create a board from a GET/mount.
Existing Arenas with no boards need one explicit Create board recovery action;
existing multiple boards keep their selection/URLs and are not merged or deleted.

Create tasks opens a modal explaining that Speculator analyzes `docs/` and relevant eligible files
within a bounded source policy. A short brief is optional when sources are useful;
an empty folder needs a brief. Show read/provider-use scope before dispatch, then
sources and skipped/truncated entries in Inspect. The target needs no pasted path
list or per-suggestion import. Preserve manual editing and source provenance.

Start is the canonical visible label. Run/Fight are not separate modes. Its compact
summary names scope/team/limits; contextual Git or permission requirements appear
inline when necessary. Routine preparation is automatic after authorization.
Do not require visiting Battle preview, accepting every spec or preparing each
worktree manually. R050e exposes bounded sequential Start and confirmed Stop,
with stage/model/task progress and retained evidence. Unsupported setup disables
Start with an explanation. R060a adds Pause/Resume on the same board: Pausing
finishes the bounded current stage, and Paused requires verified cleanup. Resume
keeps the saved stage, team and original deadline; show that paused time counts.
Keep Stop available while pausing or paused. R060b shows one Retry failed stage
button only for eligible settled provider failures, with usage, retained-edit and
retry-limit explanations. Recovered/stale controls cannot launch it. R060c adds
Skip task for eligible settled boundaries, with a confirmation naming the task
and deferred dependents. Show that edits stay retained, paused work stays paused
and continuing independent tasks may consume allowance. Keep skipped/deferred cards
unfinished; report Partial separately from Completed. Stale confirmations cannot
apply to a later task. Parallel workers and full interrupted-work recovery remain open.

R060d displays **Paused after restart** for a fully settled checkpoint, explaining
that Resume continues the saved stage with existing agents and remaining limits.
Keep recovered text and task evidence visible; stale pre-restart controls cannot
resume it. An interrupted worker still shows Needs attention, not a Resume promise.

Advanced contains additional boards, custom roles/columns, future-board team adoption,
repository setup, project check declarations and retained worktree inspection.
The current board's team is available directly beside its title.
Existing confirmations, audit/history and stale-form guards still apply there.
Do not collapse an active operation into an invisible state; show progress/cancel
and a link to its details. Optional advanced controls must not occupy the normal
empty-state checklist. The board selector is unnecessary when only one exists.

## Task and activity inspector

Clicking a card opens its spec, criteria, original sources, candidate, review
comments and attempts. Editing and manual column movement use the same domain
gates as automated moves; dragging into Completed can never forge a review.
Use a labelled **+** in Specs and ToDo to open the manual task dialog in that
column. Later columns have no add button because a manual draft cannot bypass
execution/review. Keep dirty text when the dialog closes; changing task still
requires the existing discard choice.

Active cards show task, role/worker, agent, requested model (actual when reported),
public activity, elapsed time, waiting reason and relevant controls. Parallel
instances have distinct labels, such as Implementor 2. No private chain-of-thought.
Progress uses completed/authorized tasks, active/blocked counts and criteria,
never an invented percent of model thinking. Scope changes alter the denominator
visibly. Global and Arena Tabula Gladiatorum use the same committed records.

Logs open in Inspect with pagination, keyboard access and optional follow-tail;
scrolling up stops following. Link only to actual authorized redacted log files.
Expose timestamp/role/attempt filters and truncation. Browser reconnect retains
progress and available evidence; a spinner alone is not sufficient activity.

## Interaction rules

One obvious primary action per state. Useful errors stay visible beside the
relevant control; technical adapter details belong in Inspect. Genuine attention
states explain the needed input. Use existing accessible HEEx forms/dialogs,
LiveView/domain validation and small hooks only for native browser behavior.
Preserve text, focus, scroll, checked state and disclosures through live updates.
Provide keyboard/menu alternatives to every drag action, focus return, adequate
targets, non-color status and quiet screen-reader announcements.

Profile confirmations remain action-specific and revision-guarded: consume the
submitted action, retain unrelated selections, reject stale recovery and clear
profile consent on executable/account changes. Fresh connection inspection clears
model-usage consent while preserving selected models. Hide sign-in when connected.
Team is one revisioned role editor; stale bindings stay visible and never silently
fall back. Saving settings does not grant execution.

## Incremental delivery

R002 creates a default board with each new Arena, suggests its folder name and
opens the board immediately. Existing Arena routes read their first board without
creating records. Create tasks is a button on the board; repository/team/extra-board controls are
under Advanced. R080a opens planning, repository setup, extra-board creation and
manual task editing in the shared native dialog. Escape/close returns focus;
LiveView patches retain the open state and unsaved inputs. Closing does not
cancel an operation. Ongoing planning remains visible outside its dialog.
**Board team**, **Team for new boards** and **Use saved team** replace technical
version labels in ordinary controls; **Team history** retains dated versions.
R040l adds **Read project folder**, exact source disclosures, skipped/limit counts,
local progress/cancel and an optional brief with nonempty sources. It retains
manual document selection and separately consented Speculator planning.
R040m creates validated cards automatically; legacy requests retain individual
imports. R050e implements bounded sequential Start. Keep the remaining runtime,
recovery and provider acceptance limits visible. [Development](DEVELOPMENT.md) describes available operations.

## Agent wizard and routes

R020i makes `/agents` the agent roster, with one **Add agent** action and an
**Edit** link and confirmed **Disconnect** per named connection. Disconnect
clears that agent's current role assignments with retained history. An unfinished
battle using it refuses disconnection; other agents remain unchanged. `/agents/new` and `/agents/<ID>` use the
four-step wizard. New connections choose Codex or Cursor and a display name.
Team's agent selector lists those names and filters each role's model selector
independently. Changing an agent clears that role's unsaved model choice. Cursor
setup and task execution are available; optional model tests and initial planning remain unavailable. Existing Codex
profiles and immutable assignments are preserved. No single global agent selector.

R080e shows **Disconnected** after verified native sign-out, and disables repeat
Disconnect. It also derives this display from exact older completed logout
receipts; a signed-out inspection or failed/uncertain operation is not success.
Edit opens authorization when disconnected even if old model selections remain.
Disconnect preserves the named connection so the user can reconnect it; complete
local workspace reset is the separately confirmed offline developer helper.

R020j aligns URLs with navigation: **Agents** uses `/agents` and **Settings** uses
`/settings`. Wizard pages stay under `/agents/:id`. Old `/about` and
`/settings/:id` bookmarks redirect to the corresponding canonical pages. Tray
shortcuts use the same routes; all destination pages require a live session.

## Agent wizard navigation (R020k)

R020q prefills a new connection's editable provider name and discovered executable.
Keep overrides in Executable details; a missing CLI needs a visible explanation,
not a hidden-field validation bubble. Signed-out step 2 shows Sign in, not Refresh.
The click preopens a pending tab; AgentLogin follows only the matching command's
session-protected local redirect when ready. The same control becomes Continue
as a blocked/closed-tab or reconnect fallback. No raw provider URL reaches LiveView
assigns or the hook. Navigation/reconnect never opens a tab or replays login.

Step 2 groups Back and **Next: Select models** as persistent navigation. Next is
disabled with account guidance before connection and during active setup. A
connected account with failed/expired catalog observations may still open step 3;
show the unavailable list and **Refresh models** there. Refresh uses the same
scoped, revision-guarded inspection command as step 2. Keep model choices through
Back/Next and live updates. Only a fresh catalog allows selection/review/save;
navigation alone launches no runtime and grants no authority.

## Kanban references (R080a)

[Vibe Kanban: Creating Tasks](https://www.vibekanban.com/docs/core-features/creating-tasks)
uses an explicit plus control and distinguishes creating from starting work.
[GitHub Projects: Adding items](https://docs.github.com/en/issues/planning-and-tracking-with-projects/managing-items-in-your-project/adding-items-to-your-project)
keeps draft creation in the project view. Cuckoding adopts contextual creation and
on-demand details, with its own five-column board, Speculator planning and Secutor
review. These references inform interaction only; no external source code or
artwork is copied. Start remains the separate execution authorization.
