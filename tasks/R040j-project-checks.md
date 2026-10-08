# R040j — Saved project checks

Status: complete; implemented, verified and merged to local main (`6a83d06`). Owner: Codex.

- Let the user configure up to eight named Arena checks with an executable name,
  literal argument list, relative working directory and finite timeout. Do not
  infer commands from task text, source files or provider output.
- Preview the exact normalized declarations and require fresh confirmation before
  saving any additions, changes or removals. Keep declared commands unwrapped.
- Save immutable Arena-scoped revisions, an idempotent command and public audit
  event atomically. Reject stale editors/key conflicts and preserve earlier facts.
- Keep the editor, errors and keyboard-accessible disclosures stable through live
  updates; protect recovered forms and reload of unsaved changes. Enforce sessions.
- Preserve old databases with an additive forward-only migration and prior-copy
  checks. Configuration grants no execution; future battle admission must bind
  a revision and verify executable identity, worktree paths and runtime grants.
- Verify focused domain/LiveView/adversarial/migration cases and packaged browser
  restart behavior. Update README, AGENTS and docs, merge local main and remove
  the branch. Runner grants and battle execution remain separate open gates.

Evidence: [worklog](../worklog/2026-10-08-R040j-project-checks.md).
