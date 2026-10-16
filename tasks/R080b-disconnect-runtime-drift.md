# R080b — Disconnect after executable drift

Status: implemented and verified locally, 2026-10-15; integration pending.

- [x] Reproduce the roster's generic failure when the selected executable no
  longer matches its verified identity, including an already signed-out agent.
- [x] Confirmed Disconnect disables that exact saved connection and unassigns
  current default/Arena/board roles without launching an unverified executable.
  Preserve history, other connections and immutable battle bindings; refuse
  active battles, busy setup, stale revisions and foreign/recovered forms.
- [x] Keep verified native logout unchanged. A local-only fallback must say
  provider sign-out was not attempted and preserve the provider-owned profile.
  Record an idempotent, audited transaction; never infer provider logout.
- [ ] Add domain/LiveView regression checks, update docs/AGENTS/README, rebuild
  and verify the running saved-workspace app, then merge into local main.

No silent reassignment to c2, profile deletion or provider inference is authorized.

[Verification and handoff](../worklog/2026-10-15-R080b-disconnect-runtime-drift.md).
