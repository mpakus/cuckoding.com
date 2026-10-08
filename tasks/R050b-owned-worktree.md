# R050b — Owned Git worktree preparation

Status: completed, 2026-10-08. Branch: `feature/R050b-owned-worktree`.

Prepare a detached, locked checkout from a fresh explicitly selected Arena HEAD.
This setup capability grants no agent/check execution and does not change Battle preview.

- [x] Require separate confirmation and the latest committed Git observation; freeze HEAD and folder identity in a durable idempotent command.
- [x] Create a bounded app-owned worktree with a private ownership record, fixed Git operations, no hooks/filters/network or original-checkout edits.
- [x] Reject unsafe tree/config/path layouts; retain partial effects on cancellation, expiry and restart without replay or cleanup.
- [x] Expose consent, progress/cancel and retained receipts through session-protected Repository setup.
- [x] Add focused domain/native/UI regressions, run quality gates, verify a packaged fixture and update documentation.
- [x] Commit and merge local main; delete the merged feature branch. No push.

Evidence: [worklog](../worklog/2026-10-08-R050b-owned-worktree.md).
160 Elixir tests, 38 Rust tests, static checks, bundled smoke, real Git/browser and
restart fixtures passed. R050 Start authority and provider execution remain open.
