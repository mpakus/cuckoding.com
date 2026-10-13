# Product contract

Updated 2026-10-10 from the original user story and the Arena simplification.
This is the target experience. The [implementation checklist](PLAN.md) distinguishes
available setup, folder analysis and task creation from unfinished battle execution.

## The story

Cuckoding (short name **CC**) helps one developer set up local coding agents
in about ten minutes, then lets the team carry out simple processes autonomously.
It opens from the macOS top bar into the default browser. The interface feels
like a modern TUI with normal mouse controls: restrained typography, clear
status text, a narrow sidebar and one or two primary content regions.

1. **Authorize agents.** In Agents, discover installed runtimes such as Claude
   Code, Cursor, Codex and Hermes; connect each through its own supported login.
   Keep authorization reusable across roles, Arenas, battles and app restarts.
2. **Fetch models.** After authorization, discover available models and cache
   validated IDs, labels, capabilities and freshness in SQLite. Explain discovery
   failure separately from login failure; offer runtime default/manual ID only
   when the adapter supports it.
3. **Choose the team.** Use Speculator, Implementor and Secutor, or add named
   roles. Each role selects a saved agent and model. Also assign **Summa Rudis**,
   the coordinator. Save this default team once; Arenas inherit it.
4. **Add a folder.** An Arena is one local folder, empty or containing docs/code.
   Default its name from the folder and inherit the saved team. Adding a folder
   does not launch agents or alter project files.
5. **Use the default Tabula.** Create Specs, ToDo, In Process, Review, Completed
   automatically with the saved roles. Creating/naming a board is not a required
   user step. Additional boards, custom columns and role overrides remain available
   through advanced settings.
6. **Create tasks.** Ask the assigned Speculator to analyze `docs/` first and the
   relevant files in the folder, with an optional brief. Show the folder scope and
   provider usage at the action. The host reads bounded eligible files, freezes
   sources, validates the proposals and creates cards automatically. No manual
   path list or per-card import is required. Tasks remain editable before Start.
7. **Start.** Press one execution button on the same Arena page. Summa Rudis
   coordinates the saved team and automatic card movement through work, review
   and correction until completion, stop or a genuine blocker. Ordinary task
   assignment, spec preparation, coding, reviews and bounded retries need no
   further approval. Git initialization asks first only when needed; initial
   commit scope is disclosed separately. Planning is usable without Git.
8. **Watch Tabula Gladiatorum.** The global dashboard covers every Arena; an Arena
   dashboard focuses on its Tabulae and workers. Show role, agent, model, task,
   public activity, elapsed time, progress and controls. Logs open on demand.
   Clone workers into separate sessions/worktrees to work on independent tasks
   concurrently.

## Vocabulary

| Term | Meaning |
| --- | --- |
| Cuckoding / CC | Product / short product name |
| Arena | Project: one selected local folder and its settings |
| Tabula | A Kanban board belonging to an Arena |
| Battle | One authorized execution of a Tabula's task set |
| Tabula Gladiatorum | Dashboard, globally or filtered to one Arena |
| Agent | Saved connection to a locally installed runtime |
| Model | Model selected through that runtime; distinct from the runtime |
| Role | Named responsibility, instructions, agent/model assignment and grant |
| Worker | One running instance of a role; a clone is another independent instance |
| Spec / task / attempt | Versioned intent / unit of work / one stage execution |

“Arena” is canonical; “Area” in the user story is treated as the same project.
“Battle” names execution, not a second kind of project. UI labels use these terms
with plain-language helper text on first use.

## Responsibilities

| Role | Responsibility | Authority |
| --- | --- | --- |
| Speculator | Read the brief/documents; write specs, tasks, dependencies and acceptance criteria; revise after review comments | Read repository; submit structured proposals |
| Implementor | Implement the accepted task and run checks in its assigned worktree | Write within the approved worktree and execute permitted commands |
| Secutor | Independently compare the exact candidate with specs and checks; pass, return comments or block | Read candidate and run approved verification; no source fixes in the review session |
| Summa Rudis | Coordinate the battle; prioritize, dispatch, route feedback, resolve workflow disputes, request clarification when necessary | Propose bounded control actions; no direct DB, shell, policy or Git authority |
| Custom role | User-defined work at an explicit step, with a chosen name, agent and model | Read-only by default; execution/write grants require confirmation |

Secutor is the completion judge. Summa Rudis manages the process and may request
another review or clarification; it cannot turn a failed review into a pass,
drop acceptance criteria, or enlarge its authority. Phoenix validates every
proposal and applies the actual transition. The same agent/model may fill all
four roles, but review uses an independent session and evidence. Separate models
are an option, not an onboarding requirement.

## The simple Arena contract

**Add folder → Create tasks → Start** is the normal path after one-time Agents and
Team setup. **Start** is the single execution label; Run/Fight/Start battle describe
the same battle, not extra buttons or modes. The Arena page itself is its dashboard.

One primary region is the board. A compact top area shows folder, goal and current
action; task details and logs open in one optional inspector. Before tasks exist,
show a brief field and Create tasks. After valid tasks exist, show Start. During
work, show current activity and Pause/Stop. Settings and evidence are disclosed
when requested or when an actual blocker needs a decision.

Do not require a separate Tabula wizard, Battle preview page, manually imported
cards, accepted-spec ceremony, prepared worktree or repeated agent assignments.
Keep their useful evidence/controls in Advanced or Inspect. Existing records and
custom boards must remain accessible; simplifying navigation never discards them.
If existing Arenas contain several boards, remember the selected one or ask once;
never silently run all boards.

Folder analysis is bounded reading, not permission to execute repository code.
Skipped/unsupported files and truncation are visible. An empty folder needs a
brief; contradictory or insufficient material gets one useful clarification.
Changed scope or provider selection requires fresh planning intent. Re-analysis
adds a new proposal revision and never overwrites user edits or creates duplicate
cards on retries. [Flow](FLOW.md) owns the detailed state/authority contract.

## Setup target

Measure **first launch → ready to Start in ten minutes** for a user with
one supported runtime installed and an eligible provider account. The release
gate also measures the full path when a runtime must be installed; report those
times separately rather than hiding downloads or provider login delays.

Set up Agents → Team once. Each project then uses Add folder → Create tasks → Start.
It needs no YAML edits, database setup, terminal orchestration, custom plugin
selection or per-task agent assignment. One connected runtime can serve all
roles. Defaults include the board, role instructions and finite execution limits;
the user must choose a real supported model and a Summa Rudis binding.

## First complete release

The release includes the entire story, including custom roles/columns, Hermes
adapter assessment, parallel workers, live logs, restarts and sleep recovery.
Provider support is earned separately for each installed/pinned version; a
runtime lacking safe required capabilities is shown as unavailable with a reason.
An unsupported card does not count as completed support. A missing provider
cannot prevent the user from running another supported one.

Local completion yields a reviewable battle branch, task evidence and a final
summary. The original checkout remains intact. Push, pull request creation,
merge and deployment are separate human actions; publishing automation is
outside the first rebuild.

Defer a plugin marketplace, container/remote runners, general workflow graphs,
cross-project knowledge publication, autonomous memory extraction, pricing
analytics and competitive positioning. The separately requested public site is
tracked in R015/R016 and does not imply additional app capabilities. Keep project
documents/specs as ordinary readable Markdown with scoped metadata in SQLite.
No vector database or external indexing service is needed for the described flow.

## Success measures

- Timed ten-minute setup with the prerequisites stated above.
- One Start reaches verified local completion without ordinary task-level
  assignment/approval, including at least one review correction.
- At least two independent tasks execute concurrently without duplicate claims
  or lost changes; dependent tasks see their completed prerequisites.
- Closing the browser, app restart, provider interruption and a sleep/wake cycle
  preserve state and evidence.
- A user can identify every active worker's task and next safe action from either
  dashboard; completed, blocked, skipped and cancelled are never conflated.
