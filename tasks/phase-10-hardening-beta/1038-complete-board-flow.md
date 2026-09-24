---
status: blocked
owner: codex
started_at: 2026-09-24
worklog: worklog/2026-09-24-1038-complete-board-flow.md
---

# 1038 — Complete the project-to-board agent flow

Preserve the user's full active goal; source-only or fixture-only success does
not establish a ready-to-use local application.

- [ ] Create a project, add/reuse agents with independent models, assign roles and create a board.
- [ ] Select a Speculator/analysis agent to generate tasks/specs from a prompt or project Markdown files.
- [ ] Select another model to review proposed tasks, retain comments, improve descriptions/specs and produce a report before import.
- [ ] Execute Speculator → Implementor → Reviewer with validated comments returning through Cuckoding to Speculator; preserve historical snapshots and finite budgets.
- [ ] Advance eligible cards through the flow and to local completion under the user's explicit run policy; remote handoff remains separately approved.
- [ ] Support user-added roles and reviewed permissions without permitting instruction-based escalation.
- [ ] Run independent tasks concurrently and show actual owner, model, stage, elapsed time and state with accessible animation on dashboard/board.
- [ ] Pause/resume or stop one task and pause/stop all Cuckoding work with durable state and owned-process control.
- [ ] Pass focused/full relevant tests, security/transition/recovery gates and rendered keyboard/mobile checks.
- [ ] Merge all goal changes into main, build and launch one current app, and verify the complete local journey with explicit evidence and remaining limitations.

## Evidence and remaining acceptance

All listed capabilities now have source implementations and focused regression
coverage. The combined suite has 10 properties and 333 tests. An isolated CLI
fixture exercised planning → independent model review/report → import → two
Speculator/Implementor/Reviewer cycles → local completion, with a passing
candidate test. This is not real-provider acceptance.

Browser checks covered registration, executable discovery/manual override,
reusable sign-in/model selection, and desktop/mobile board rendering. After the
stalled test tab cleared, the clicked fixture flow reached Done and exercised
two concurrent tasks plus individual/workspace pause and resume. Live updates
were found collapsing native disclosures; preserving browser-owned open state
fixed that failure. Native folder-picker and confirmation automation, visible
motion and real-provider acceptance remain separate open checks.
The rebuilt native app has no saved provider sign-in; its authenticated UI and
real-provider full-flow check still need user participation. Preserve these
open acceptance boxes until that evidence exists. See the worklog for source,
bundle, data-preservation and running-instance evidence separately.

User-dependent handoff: open the rebuilt Cuckoding menu-bar app and connect an
app-owned provider account. The same missing native authorization has persisted
across three goal continuations; independent fixture, UI, merge and packaging
work is finished. Resume native acceptance after sign-in, without treating the
fixture evidence as completion of the full goal.
