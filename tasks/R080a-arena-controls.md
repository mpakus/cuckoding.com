# R080a — Direct agent and Arena controls

Status: implementation verified, 2026-10-14. Branch: `feature/R080a-arena-controls`.
Bundled rebuild/relaunch pending graceful Quit of the existing saved app.

- [x] Each agent has confirmed Disconnect; unassign its roles in current default,
  Arena and board teams with immutable history, exact connection scope and no
  changes to active/frozen execution. Preserve unrelated agents and instructions.
- [x] Aged catalogs alone do not disable saved bindings. Keep fresh catalog gates
  for new choices, failed refresh/sign-out/drift refusal and runtime validation.
- [x] Create tasks, Repository setup and Add board open accessible dialogs.
  Put manual task creation on the board as +; retain text and operation status.
- [x] Replace technical team-version copy with plain labels; retain inspection
  history and guarded explicit team replacement.
- [x] Research primary Kanban references; use existing UI/native facilities.
- [x] Focused checks, full quality, production assets/compile, source smoke and
  desktop/narrow browser verification; update docs/AGENTS/README.
- [ ] Replace the running bundle, packaged smoke and relaunch the preserved saved
  workspace after graceful Quit. No forced shutdown or provider calls.

[Verification and handoff](../worklog/2026-10-14-R080a-arena-controls.md). Local
integration does not publish or update an already-running application.
