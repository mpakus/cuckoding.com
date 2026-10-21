# R080h — Task execution evidence in its existing dialog

Status: complete, 2026-10-21. [Evidence](../worklog/2026-10-21-R080h-task-evidence.md).
Merged locally as `42e1741`; task branch deleted. No publication.

- [x] Open a saved task's execution history inside its existing details dialog:
  frozen revision/criteria, public review feedback, exact agent/model, candidate,
  retained edits and inspection/check evidence. Clearly separate evidence from
  current draft text and expired/rejected work from accepted completion.
- [x] Bound every read to the server-owned Arena/Tabula/task; page attempts and
  earlier executions without exposing request/context/raw provider payloads.
- [x] Reuse guarded LiveComponents and native dialog behavior, preserve dirty
  task input, selected history and disclosure/scroll state through updates.
- [x] Verify scope/privacy, pagination/history, reconnect/expired-session behavior
  and rendered keyboard/narrow use. Update docs/AGENTS/README and merge local main.
