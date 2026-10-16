# R080c — Fast, polished setup-to-Start flow

Status: implemented and verified locally, 2026-10-15. Local integration pending.

- [x] Keep the visible journey Agents → Roles → Arena & Tabula → Create tasks →
  Start, with saved progress and a useful Home next action instead of restarting
  onboarding. Navigation alone never launches a provider or changes saved data.
- [x] Make role agent/model choices immediately visible. Preserve custom roles,
  instructions, dirty text, independent named connections and revision guards.
- [x] Put the Arena board and primary action first. Keep bounded Start authority
  and independent review visible in a compact summary, with full details on demand.
  Expose explicit board-team review without silent adoption or reassignment.
- [x] Polish shared black/green surfaces, spacing, focus and narrow layouts with
  existing LiveView components/CSS, no new dependency or frontend framework.
- [x] Add focused LiveView checks, update docs/AGENTS/README, run quality, inspect
  the desktop role editor and rebuild/reopen the preserved workspace safely.
- [ ] Complete narrow-browser and packaged interactive flow checks; browser
  automation was interrupted by concurrent user control. Timed acceptance remains open.
- [ ] Merge this verified implementation slice to local main.

The ten-minute target remains a timed real-provider acceptance gate, not a promise
established by fixture/UI tests. No provider usage or real battle is authorized.

[Worklog](../worklog/2026-10-15-R080c-fast-simple-flow.md).
