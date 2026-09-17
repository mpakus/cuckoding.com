# Worklog — Planning Pack v2 Revision

## Metadata

- Date/time (UTC): 2026-09-16
- Task: Planning pack revision
- Status: done
- Owner: Project authoring session
- Environment: documentation-only planning pack

## Intended outcome

Apply the seven revision requests: remove Docker from the MVP, choose a menubar-only shell with the UI in the browser, add long-running-run and power handling, review knowledge-compression approaches, convert XERJ/RTK/Ponytail into plugins, strengthen tests and remove contradictions, and add dashboard views for roles/agents and knowledge growth/use.

## Work performed

- Replaced `docs/DOCKER_SANDBOX.md` with `docs/EXECUTION_ENVIRONMENTS.md` (LocalProcessRunner, ports, preview URLs, honest limitations, container runner plugin path).
- Added `docs/DESKTOP_SHELL.md` comparing Tauri tray-only, Swift/AppKit, elixir-desktop, and Burrito; decision recorded as ADR-011.
- Added `docs/LONG_RUNNING_AND_POWER.md` (assertions, sleep-gap detection, reconciliation, unattended mode, budgets).
- Added `docs/PLUGINS.md`; moved XERJ/RTK/Ponytail specs to `docs/plugins/` as plugin specifications.
- Rewrote `docs/KNOWLEDGE_COMPRESSION.md` with a landscape review and a Markdown-first pipeline with usage tracking.
- Rewrote `docs/UI_DASHBOARD.md` with Agent Floor, Knowledge Growth, and Knowledge Lineage/Usage views.
- Fixed contradictions: release handoff is a system stage (no agent token), advisory vs enforced policy fields, single task-state vocabulary, SecretStore owned by Phoenix, agent location fixed to host.
- Expanded `docs/TESTING.md` with a per-component matrix, fixtures, and twelve end-to-end scenarios.
- Regenerated `tasks/` for the new phase order with a walking skeleton at 0405.
- Updated examples in `.cuckoding/` and skills in `.agents/skills/`.

## Decisions

See ADR-011 through ADR-016 in `docs/DECISIONS.md`.

## Handoff

Start with Phase 0. Task 0001 must settle name, license, pricing hypothesis, and competitive position before implementation.
