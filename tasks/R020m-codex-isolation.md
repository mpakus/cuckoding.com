# R020m — Codex execution isolation conformance

Status: complete, 2026-10-13. Branch: `feature/R020m-codex-isolation`.

Claimed as the next R020 execution prerequisite. This tests fixed commands in
disposable app-owned fixtures; it does not run model inference or Arena tasks.

- [x] Verify the installed Codex sandbox interface and reject unsupported versions.
- [x] Exercise read-only and writing grants in two isolated workspaces, including
  sibling/profile/protected-path/network canaries and owned cancellation/timeout.
- [x] Save exact executable/version-bound public receipts through the command
  ledger; reject stale, cancelled and expired success without automatic replay.
- [x] Add an optional diagnostic with clear progress, cancellation and result;
  preserve Agents/Team and the four-step setup flow.
- [x] Run focused/native/full checks, update docs/README/AGENTS and merge local main.

Evidence: [worklog](../worklog/2026-10-13-R020m-codex-isolation.md).

Provider tool turns, battle admission and autonomous work/review remain separate
open gates. A successful sandbox check is dated evidence, never execution authority.
