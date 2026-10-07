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
No separate Agent Floor, knowledge graph or competing start screen.

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
Preserve entered text, scroll position, focus and disclosures during live updates.
Validation errors remain visible and linked to fields.

Drag-and-drop is optional: menu/keyboard actions provide every allowed move.
Manual column moves invoke the same gates as automated moves; dragging into
Completed cannot forge a review. Provide focus return, clear focus rings,
screen-reader labels, live announcements without event spam, adequate targets
and horizontal board scrolling on narrow widths. No color-only status.
