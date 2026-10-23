# R060p — Close interrupted provider/native pairs without accepting work

Status: implemented and verified; local integration pending, 2026-10-23. Base `08d843f`.

- [x] Freeze a new policy in Starts for a restart-interrupted provider plus
  capture/preparation pair. Preserve old policies and every original claim.
- [x] Read provider closure first, then the exact retained native receipt in
  exclusive supervised workers. Never replay a turn/Git mutation or advance a
  card/head/checkpoint. Only verified closure of all claims permits Stop.
- [x] Keep failed/missing/foreign proof blocked, timestamps/public Inspect
  evidence, original deadlines/slots/bindings/budgets and restart durability.
- [x] Verify domain, OTP, UI and compatibility; update docs/AGENTS/README.
- [ ] Commit and merge local main without publication; delete the feature branch.

No new native operation, migration, inference or broader process recovery.
Evidence: [worklog](../worklog/2026-10-23-R060p-mixed-closure.md).
