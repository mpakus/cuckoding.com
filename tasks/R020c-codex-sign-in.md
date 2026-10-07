# R020c — Private Codex sign-in and sign-out

Status: completed, 2026-10-07. Branch: `feature/r020c-codex-sign-in`.
Parent: [R020](R020-codex-connection.md).

- [x] Confirm private-profile sign-in/out with a supported unchanged executable; persist intent before launch and invalidate old account/catalog observations.
- [x] Extend the fixed native helper with managed ChatGPT browser login, matching completion, cancellation and logout; never start a thread/turn or import credentials.
- [x] Keep validated official login links transient, bounded and available after browser reconnect; never store links, login IDs, credentials or raw errors in SQLite/logs.
- [x] Serialize profile access, bound login duration, retain uncertain/interrupted state without replay, and hold cancellation until helper cleanup.
- [x] Refresh account/catalog after success; present progress, elapsed time, retry, cancel and private sign-out in LiveView.
- [x] Run focused adversarial/protocol/durable/UI checks and packaged smoke; distinguish fixture login success from human-completed real account acceptance.
- [x] Update docs, AGENTS and README; commit and merge local main. Real scoped turns remain R020 work.
