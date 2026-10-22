# R070c — One attempt-bound stage receipt boundary

Status: complete, 2026-10-21.

- [x] Extract the existing closed envelope/stage/provider/check/session validation
  from the large battle coordinator into `Battles.Receipts`; use the same validator
  for settlement, cancellation/Stop, expiry, review failure and recovery.
- [x] Keep validation bound to the immutable attempt, never a current-task cursor.
  Preserve all historical policies, provider normalization, fresh-session checks,
  candidate/check gates and transaction ownership. No migration or new grant.
- [x] Focused contract checks, full host quality, build/smoke, docs/AGENTS/README
  and local main merge. This is a prerequisite, not parallel Start acceptance.

Evidence: [worklog](../worklog/2026-10-21-R070c-stage-receipts.md).
