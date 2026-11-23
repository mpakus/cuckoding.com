# BOSS visual system

The BOSS desktop/web orchestrator uses a minimalist, modern-futuristic dark
mission-control visual system (`#090b10` obsidian canvas, `#10141d` carbon-slate
panels, crisp `#1f2736` hairline borders, `#2dd4bf` electric cyan-emerald accents,
and high-contrast `#f1f5f9` / `#cbd5e1` slate typography). The standalone public
marketing site in `site/` retains its own editorial broadsheet styling and is
decoupled from the application shell.

`assets/css/app.css` owns semantic Tailwind `@theme` tokens (`--color-paper`,
`--color-surface`, `--color-surface-raised`, `--color-ink`, `--color-body`,
`--color-muted`, `--color-forest`, `--color-sage`, `--color-peach`, `--color-line`,
`--color-control-line`, `--color-warning`, `--color-danger`) and shared `app-*`
components. Interactive controls maintain WCAG AA+ contrast, explicit borders and
2 px visible keyboard focus rings.

## Progressive disclosure & workspace density

- **Top Command Bar (`root.html.heex`)**: a single-row 52 px sticky blurred glass
  bar (`BOSS` mark, `Projects`, `Agents`) with no global footer so vertical space
  is dedicated to the workspace.
- **Project Workspace (`/projects/:id`)**: a compact single-row command header
  (project title, target branch chip, specs/docs mode pill, `Roles & models`,
  `Capacity` popover, `Prompt task control`, `Sync specs`, `Autopilot`), followed
  by a compact Autopilot HUD strip and the 5-column Kanban board above the fold.
  Task selection lists, optional CLI check overrides, safety/billing copy, and
  historical batches stay collapsed inside `<details>` disclosures until requested.
- **Kanban Cards & Task Drawer (`TaskBoard`, `DeliveryPanel`, `RunPanel`)**: cards
  surface only task title, live status/agent/dependency pills, animated progress
  track when active, and revision drift badges; verbose revision/path provenance
  remains accessible in screen-reader metadata and the slide-over `#task-drawer`.
  Inside `#task-drawer`, Managed Workflow, Activity & Notes, and Specification sit
  above a collapsed `Advanced & manual diagnostics` `<details>` disclosure housing
  manual Codex runs, candidate checks/reviews, and raw transition events.
- **Agents & Roles (`/agents`)**: places the 3-column Orchestration Roles deck
  (`Analytic`, `Implementer`, `Reviewer`) at the top with inline auto-saving
  bindings, followed by compact Connected CLI Agent cards with collapsible model
  catalogs and a side `Connect & authorize CLI` panel.

## Motion & Three.js pipeline telemetry

`assets/js/motion.mjs` synchronizes document motion with the OS
`prefers-reduced-motion` preference (the visible **Pause motion** toggle belongs
only to the standalone marketing site in `site/`, not the desktop application).
Motion starts disabled until JavaScript initializes and respects live
`prefers-reduced-motion` changes. Keyboard input disables pointer transitions;
buttons scale to `0.96` over `150 ms` on pointer press; the native task drawer
and modals use `overscroll-behavior: contain` and smooth `200–250 ms` entrances.

`assets/js/autopilot_flow.mjs` renders the dark obsidian/cyan-emerald Autopilot
pipeline and task pixel dashboard with Three.js (`AutopilotFlowCanvas`) on top of
accessible HTML stage badges and 44 px task links. Flow pulses run only while a
batch is active and document motion is enabled; when OS reduced motion is active
or WebGL is unavailable, the dashboard stays static and fully keyboard-operable.

The native drawer/modal hooks, URL selection, form events and workflow evidence
gates are unchanged. The redesign does not authorize a task, a provider call or
an application restart.
