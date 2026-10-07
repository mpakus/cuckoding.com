# R020b — Private Codex connection inspection

Status: complete, 2026-10-07. Branch: `feature/r020b-codex-connection-inspection`.
Parent: [R020](R020-codex-connection.md).

- [x] Require a supported, unchanged executable and explicit consent for a private profile check.
- [x] Initialize bounded app-server stdio, read account status, and request a paginated catalog only for managed ChatGPT authorization; never start a thread/turn or import personal profiles.
- [x] Persist public account observation and validated catalog separately from version readiness, preserving stale models on refresh failure.
- [x] Show source, freshness, elapsed state, cancellation and actionable outcomes in LiveView.
- [x] Verify protocol bounds, malformed/unexpected messages, canaries, cancellation/group cleanup, revision/claim protection, prior-schema copy and reconnect.
- [x] Exercise the installed Codex in a fresh app-owned profile, explicitly distinguish this from real login/model entitlement.
- [x] Update docs/AGENTS/README, commit and merge local main. Login/logout and real two-workspace turns remain R020 gates.
