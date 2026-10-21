# R060l — Retained provider closure after a lost reply

Status: complete, 2026-10-21. [Evidence](../worklog/2026-10-21-R060l-retained-provider-closure.md).

- [x] New Starts opt into exact, exclusive native provider closure intents and
  fsynced public closure receipts, before returning a Codex/Cursor task result.
- [x] Fixed bounded descriptor-relative inspection verifies the exact saved
  attempt/connection/runtime binding without launching or signalling a provider.
- [x] Restart records a separate immutable observation for an interrupted provider
  attempt. Verified closure permits confirmed Stop and releases its connection;
  never accept the lost work, advance cards/head, or enable Resume/Retry/Skip.
- [x] Missing/partial/foreign/changed evidence and older Starts remain blocked.
  Preserve all edits, private stores, deadlines, budgets and interrupted attempts.
- [x] Guarded LiveView inspection, adversarial/native/domain/restart checks,
  docs/AGENTS/README, packaged smoke and local main integration.

Hard-killed helpers without a final receipt, escaped sessions, native Git/check
interruption and physical sleep still need separate recovery acceptance.
