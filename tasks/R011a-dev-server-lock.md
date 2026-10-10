# R011a · Explain an already-running UI server

Status: complete, 2026-10-10.

- [x] Replace the raw lock-contention error with clear existing-server/restart guidance.
- [x] Preserve exclusive ownership and developer data; never unlink or steal a held lock.
- [x] Verify contention, released lock reuse and normal developer smoke/cleanup.
- [x] Stop the assistant-owned preview so the user can launch it from their terminal.
- [x] Update README, AGENTS and docs; commit and merge local main.

Evidence: [worklog](../worklog/2026-10-10-R011a-dev-server-lock.md).
