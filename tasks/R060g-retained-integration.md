# R060g — Reconcile a retained integration receipt

Status: verified and merged locally into main as `22d5d1f`, 2026-10-15.

- [x] New Starts freeze `native_recovery: retained-integration-v1`; historical
  snapshots receive no new authority.
- [x] Inspect a completed native integration through a fixed read-only operation:
  exact original intent/publication/receipt, source identity, app ref, candidate
  ancestry and owned worktree bytes. Never recreate a missing receipt or move a ref.
- [x] Reconcile only a restart-interrupted integration in a supervised async
  worker. Retain the interrupted attempt unchanged and append a durable observation.
  A verified in-budget outcome advances once to Paused, requiring explicit Resume.
- [x] Missing/foreign/changed evidence stays needs-attention; expired outcomes may
  prove closure for Stop but never advance. Preserve controls, bindings and budgets.
- [x] Cover crash/restart, partial publication, drift, cancellation and duplicate
  observations with native/domain/worker checks; update docs/AGENTS/README and
  verify the rebuilt saved workspace.
- [x] Merged into local main; merged branch deleted.

Scope excludes provider-session recovery, absent native receipts, sleep/leases,
parallel workers and real-account acceptance.

Evidence: 104 focused and 339 full Elixir tests passed; 74 native tests passed,
five explicit runtime/provider tests skipped. Native formatting/Clippy, source
and packaged smoke, build and saved-data comparison passed.
[Worklog](../worklog/2026-10-15-R060g-retained-integration.md).
