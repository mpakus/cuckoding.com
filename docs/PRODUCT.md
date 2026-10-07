# Product contract

Status: rebuild specification, 2026-10-06. All application capabilities below
are targets until the [implementation checklist](PLAN.md) records fresh evidence.

## The story

Cuckoding (short name **CCoding**) helps one developer set up local coding agents
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
4. **Create an Arena.** Choose a local folder, empty or containing documents/code.
   Inspect it first. If Git is absent, explicitly ask before initializing it.
   An initial commit is a separate disclosed Git mutation; preview its files.
5. **Create a Tabula.** Start with Specs, ToDo, In Process, Review, Completed.
   Assign roles to working columns. Add or rename columns without bypassing
   review, completion or permission rules.
6. **Describe the work.** Ask a selected role, usually Speculator, to create
   specifications and tasks from a description, selected files or a folder such
   as `docs/`. Show the resulting tasks and sources; permit edits before starting.
7. **Start battle.** From the Arena's selected Tabula, press one button.
   Summa Rudis coordinates the saved team, dispatches eligible work and handles
   review returns. Tasks move automatically until completed, stopped or blocked.
   Routine coding, reviews, corrections and bounded recovery require no further
   user approval inside the authorized scope.
8. **Watch Tabula Gladiatorum.** The global dashboard covers every Arena; an Arena
   dashboard focuses on its Tabulae and workers. Show role, agent, model, task,
   public activity, elapsed time, progress and controls. Logs open on demand.
   Clone workers into separate sessions/worktrees to work on independent tasks
   concurrently.

## Vocabulary

| Term | Meaning |
| --- | --- |
| Cuckoding / CCoding | Product / short product name |
| Arena | Project: one selected local repository and its settings |
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

## Setup target

Measure **first launch → ready to Start battle in ten minutes** for a user with
one supported runtime installed and an eligible provider account. The release
gate also measures the full path when a runtime must be installed; report those
times separately rather than hiding downloads or provider login delays.

The guided path is Agents → Team → Arena → Tabula → Describe → Start battle.
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
analytics, competitive positioning and a public-site redesign. Keep project
documents/specs as ordinary readable Markdown with scoped metadata in SQLite.
No vector database or external indexing service is needed for the described flow.

## Success measures

- Timed ten-minute setup with the prerequisites stated above.
- One Start battle reaches verified local completion without ordinary task-level
  assignment/approval, including at least one review correction.
- At least two independent tasks execute concurrently without duplicate claims
  or lost changes; dependent tasks see their completed prerequisites.
- Closing the browser, app restart, provider interruption and a sleep/wake cycle
  preserve state and evidence.
- A user can identify every active worker's task and next safe action from either
  dashboard; completed, blocked, skipped and cancelled are never conflated.
