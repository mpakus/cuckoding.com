# R050a — Battle preparation preview

Status: complete; implemented, verified and merged to local main (`6899090`). Owner: Codex.

- Give each Tabula a session-protected, read-only Battle preview using its
  assigned team, all saved tasks, current accepted Markdown, prerequisite
  revisions, Arena checks and latest Git observation.
- Show exact revision/receipt references and actionable missing/stale states.
  ToDo alone, a catalog binding or a Git HEAD observation must not imply execution
  readiness. Custom roles remain planning-only. Specs preparation stays covered
  by the future single Start authority, not a new mandatory approval per task.
- Validate retained specification bytes using the existing private reader. Never
  read Arena files, run Git/provider/check commands or write state from the preview.
- Mark displayed evidence stale on updates and after one minute; explicit Refresh
  rebuilds it. Preserve keyboard-operable disclosures. Guard scope and sessions.
- Cover scope, stale prerequisites/artifacts/catalog/Git observations, saved-team
  adoption, empty checks, no effects, refresh/reconnect and session expiry.
- Run proportionate quality and packaged browser checks, update README/AGENTS/docs,
  merge to local main and delete the merged branch. Actual battle authorization,
  worktrees, execution grants, check runs and the agent loop remain open.

Evidence: [worklog](../worklog/2026-10-08-R050a-battle-preview.md).
