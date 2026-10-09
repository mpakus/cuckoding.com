# Interface contract

Minimal, futuristic and modern; TUI-inspired but fully mouse-friendly.
Use Phoenix LiveView, HEEx and Tailwind. No terminal emulator, second frontend
framework or decorative control-room graphics.

## Visual structure

A slim sidebar and one main working surface. Each view shows **one or two primary
objects**: a list/board plus an optional inspector. “One or two” means content
regions, not two tasks; a Tabula still shows all its columns. Use generous empty
space, restrained borders, crisp type, monochrome surfaces and one accent color.
Use text/icons alongside status colors. Monospace suits labels, IDs and logs;
body text must stay comfortable to read.

Start with a dark theme respecting accessible contrast and OS reduced motion.
Avoid blinking cursors, decorative animation and dense analytics cards. Motion
only clarifies a state change; controls remain usable without it.

Sidebar: **Tabula Gladiatorum**, **Arenas**, **Agents**, **Team**, **Settings**.

R040a enables Arenas with two regions: folder selection/confirmation and registered
projects. Show the canonical path, unverified Git-entry observation and expandable
frozen team before registration. Native selection shows elapsed time and Cancel;
no agent/model is involved. Preserve name, errors and expanded roles through updates.
The project dashboard below remains future work.
No separate Agent Floor, knowledge graph or competing start screen.

R040b adds an Arena-scoped board selector, collapsed board creation and two primary
regions: a horizontally scrollable five-column Tabula and a manual task editor.
Each stage names its inherited role; unavailable delivery stages say so in text.
Cards show draft revision and no active agent. The labelled Column select provides
Specs/ToDo movement without dragging; errors stay beside Save. Dirty edits survive
live updates, discard is confirmed inline, and recovered forms cannot target a
different task. Saved history is collapsed and limited to the latest five revisions.

R040c places **Repository setup** inside the board region as a native disclosure.
Inspect Git shows a durable dated status, validated HEAD when available, and
elapsed time/Cancel while active. A recent missing result reveals a separately
confirmed Initialize Git form that names the path and exact `.git` effect. Keep
the checkbox bound to its observation through reconnect and reject stale consent.
No agent or model is involved. Git problems must not block the manual task editor.

R040d extends that disclosure with one relative path per line and a separate
preview/commit form. Blank input explicitly means an empty baseline. Render exact
paths, sizes, modes, collapsible hashes, branch, fixed author/message and distinct
confirmation. Preserve edited paths across updates; recovered/stale consent cannot
commit another selection. No drag/file browser or per-file content viewer is needed.

## Screens

| Screen | Primary content | Main action |
| --- | --- | --- |
| First launch | One setup card with Agents → Team → Arena → Tabula → Describe | Continue |
| Agents | Connection list and provider setup | Authorize / check model |
| Team | One role editor with collapsed history | Save team |
| Arena creation | Name + native folder chooser; Git status and mutation preview | Create Arena |
| Tabula setup | Default columns and role assignments; collapsed optional settings | Create Tabula |
| Describe | Brief/file selection; proposed spec/task list | Create tasks |
| Global Tabula Gladiatorum | Arena summary list; expandable current worker/activity detail | Open Arena |
| Arena Tabula Gladiatorum | Arena progress/team strip and selected Tabula board | Start battle / Pause |
| Task inspector | Spec, candidate, review comments and attempt history | Contextual resume/retry/inspect |
| Logs | Scrollable, paginated public activity and redacted output | Follow tail / open log file |

Show plain explanations beside unfamiliar names initially: “Arena · project”,
“Tabula · board”, “Summa Rudis · coordinator”, “Secutor · final review”.
The Arena dashboard contains the selected Tabula, avoiding an extra navigation
hop to see tasks. A Tabula selector supports multiple saved boards.

The current Team screen uses native disclosures, labelled text fields/selects,
one Save action and explicit saved-role removal confirmation. Four responsibilities
cannot be removed; names and instructions can change. New model choices come from
the fresh verified Codex catalog. Saved stale/missing/changed bindings stay visible.
It shows catalog availability separately from a passing diagnostic and never claims
execution is enabled. Errors and dirty drafts survive live updates; stale saves
are rejected, Reload saved asks before discarding edits, and saved state survives
reconnect. The form retains its original revision guard during browser recovery.
History is read-only and limited to the latest five entries on screen.

## Live activity

Every active row/card shows task, current role/worker, agent, requested model
(and actual model if reported), public activity, state, elapsed active/wall time
and a safe control. A cloned worker has a distinct label such as Implementor 2.
Show waiting reasons and last activity time. A running spinner alone is insufficient.

Progress is completed/total authorized tasks, active count, blocked/skipped count
and criteria status; never an invented percent of model thinking. Scope changes
update the denominator visibly. The global and Arena dashboards derive from the
same committed records. Closing/reopening the browser loses no progress.

Logs open in the inspector or a dedicated view with follow-tail off when the
user scrolls upward, keyboard navigation, loading older chunks and “Open log
file” for a real authorized redacted file. Show timestamp, role and attempt
filters. Preserve full available evidence separately from bounded UI windows;
record truncation rather than imply unbounded retention.

## Interaction rules

One obvious primary action per state. Start battle previews the saved bindings,
scope and finite limits once. Routine work then progresses autonomously. Genuine
attention items state what failed, what the team tried and what input is needed.
Keep technical adapter errors in Inspect; show useful recovery text in the flow.

Use reusable HEEx form/dialog components; one accessible modal convention,
validation in LiveView/domain contexts, small hooks only for native behavior.
Preserve entered text, checked state, scroll position, focus and disclosures during live updates.
Profile confirmations are action-specific LiveView state: preserve them through
clock/unrelated updates, clear on submission or setup changes, and refuse recovery
from an earlier form key/revision. A new page session starts unchecked.
Validation errors remain visible and linked to fields.

Drag-and-drop is optional: menu/keyboard actions provide every allowed move.
Manual column moves invoke the same gates as automated moves; dragging into
Completed cannot forge a review. Provide focus return, clear focus rings,
screen-reader labels, live announcements without event spam, adequate targets
and horizontal board scrolling on narrow widths. No color-only status.

R040e adds one **Ask Speculator** disclosure above the board. Show the frozen
role/model/team, a brief textarea and explicit provider-usage consent. Preserve
brief, focus and disclosure state through live updates; clear consent if setup
changes. Requests show state, elapsed time, owner/runtime/model and Cancel while
active. Each validated suggestion has one **Add to Specs** button, replaced by
**Added to Specs** after import. Keep unrelated unsaved manual drafts intact.
Show source brief/snapshots and the five recent requests (active first) after
reconnect. R040f nests an optional local document preview: explicit relative paths,
read state, exact expandable text/hash and separate provider consent. Changing
selection clears consent; **Use brief only** omits snapshots. Reconnect retains
evidence but requires explicit snapshot selection. Describe these as proposals
with no live Arena access, tools, accepted specs or delivery work.

R050b places **Isolated worktrees** inside Repository setup. The consent form
shows exact commit and destination and expires with its five-minute Git observation.
Changes clear stale consent. Native disclosures remain open across live updates;
progress names the user, system Git, no model, elapsed time and Cancel. The latest
ten retained attempts show status/paths after reconnect. Creation is explicitly
separate from Start and from a current-integrity claim; partial effects require
inspection and are never presented as rolled back.

R050c adds **Inspect worktree** beside each completed preparation. It keeps keyboard
focus during pending state using `aria-disabled` and a server-side busy guard.
The result names its UTC time and conservative byte comparison; progress shows
user/system Git/no model, elapsed time and Cancel. Reconnect retains the latest
observation, while text explicitly requires a fresh check before use. No repair,
delete or execution action is implied by either unchanged or changed results.
