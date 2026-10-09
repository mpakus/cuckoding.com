# R050c — Inspect retained worktrees

Status: completed, 2026-10-08. Branch: `feature/R050c-worktree-inspection`.

Inspect a completed preparation through the existing native Git ledger. This is
a read-only observation, not cleanup, execution permission or battle admission.

- [x] Bind idempotent inspection to an Arena's completed preparation and immutable identities.
- [x] Verify private ownership, checkout identity, locked detached Git registration, index and bounded raw tracked bytes; flag additional files without reading them.
- [x] Preserve source/checkout/marker/index bytes; refuse unsafe paths, foreign receipts and expired claims; never replay interrupted work.
- [x] Add session-protected progress/cancel/results, with explicit observation limits and retained history.
- [x] Cover native/domain/UI regressions, package and exercise the real fixture; update docs, README and AGENTS.
- [x] Commit and merge local main, remove the branch, and leave a separate packaged test app running. No push.

Evidence: [worklog](../worklog/2026-10-08-R050c-worktree-inspection.md).

164 Elixir tests, 42 Rust tests, static checks, bundled smoke and packaged
real-Git/browser/restart checks passed. Test instance retained separately;
Start authority and provider repository execution remain open.
