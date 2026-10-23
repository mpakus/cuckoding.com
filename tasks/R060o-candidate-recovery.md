# R060o — Retained candidate checkpoint recovery

Status: implemented, verified and merged locally to main, 2026-10-23 (`400f0bb`).

- [x] Add a fixed read-only native recovery operation for an exact interrupted
  capture with complete original intent/publication/receipt, source/ref/worktree
  and final-byte evidence. Never reconstruct evidence or repeat capture.
- [x] Freeze explicit policy in new Starts; recover one/two captures or a mixed
  capture/preparation pair through exclusive supervised reads. Retain Interrupted
  attempts, budgets, slots, bindings and original deadlines. Commit the next
  checkpoint only when every member verifies; pause for explicit Resume.
- [x] Retain dated public observations in Inspect. Failed/foreign/partial proof,
  Stop and timing/expiry races never advance work; verified closure permits Stop
  only when all original claims are closed. Preserve historical policy limits.
- [x] Verify native/domain/OTP/UI/schema compatibility and packaging; update
  docs/AGENTS/README. No new migration beyond schema seventeen.
- [x] Merge locally to main without publication; feature branch deleted.

Evidence: [worklog](../worklog/2026-10-23-R060o-candidate-recovery.md).
General subprocess checks, other interrupted native/provider effects, physical
sleep and real-account recovery acceptance remain open.
