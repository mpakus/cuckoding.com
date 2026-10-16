# R080e — Cursor disconnect and complete workspace reset

Status: verified and merged to local main as `6e886f7`, 2026-10-16.
Merged task branch deleted; no remote publication.

- [x] Mark verified native sign-out Disconnected, including existing successful
  receipts; preserve failed/cancelled/uncertain sign-out states and exact scope.
- [x] Add executable `bin/reset-agents` to reset all Cuckoding workspace state,
  not just agents, after explicit confirmation. Refuse running/busy/unrecognized
  storage; retain a private recoverable archive and preserve project folders.
- [x] Verify Cursor disconnect/reconnect and reset success/refusals on disposable
  data, update docs/AGENTS/README, run quality and rebuild the current app safely.
- [x] Merge to local main and delete the task branch. No remote publication and
  no reset of the user's saved workspace without a separate request to run it.

[Worklog](../worklog/2026-10-16-R080e-disconnect-reset.md).
