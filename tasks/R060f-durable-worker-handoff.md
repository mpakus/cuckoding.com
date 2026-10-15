# R060f — Durable worker completion before coordinator notification

Status: verified and merged locally into main as `0819a3f`, 2026-10-15.

- [x] Persist setup/battle results through existing claim-bound domain APIs inside
  their owned supervised workers before sending a completion notification.
- [x] Keep coordinators responsible for admission/monitoring, with no second
  completion write on notification. Worker failure still records interruption;
  already committed terminal facts cannot be overwritten.
- [x] Preserve cancellation, expired receipts, explicit Resume, original budgets,
  independent review and every uncertainty gate. Invalid/foreign stage receipts
  cannot supply cleanup authority.
- [x] Prove completion while a coordinator is suspended, then crash/restart it:
  setup receipts survive and battle checkpoints reopen Paused without replay.
  Cover cancellation and failure receipts at the same handoff boundary.
- [x] Update docs, AGENTS and README; run focused/full quality and source/bundle
  checks. Preserve valid Stop races and redact unexpected worker exceptions.
- [x] Merge into local main; feature branch deleted.

Evidence: 106 focused tests and 330 full quality tests passed; source/packaged
smoke and saved-workspace rebuild/relaunch passed. Browser roster and existing
Arena cards verified. [Worklog](../worklog/2026-10-15-R060f-durable-worker-handoff.md).

This closes the completed-worker/mailbox window. Native effects without a committed
valid receipt, sleep reconciliation and parallel scheduling remain open.
