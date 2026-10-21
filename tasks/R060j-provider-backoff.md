# R060j — Bounded automatic provider backoff

Status: complete, 2026-10-21. Verified and merged into local main as b99ff8f;
task branch deleted. No push/publication or native bundle replacement.

- [x] New Starts freeze an automatic backoff policy with 5/20-second waits inside
  the existing two-retry task/final budget. Only settled normalized transient
  provider failures with verified cleanup qualify; native/review/policy failures
  never retry. Historical snapshots retain manual retry only.
- [x] Persist wait/transition/cancellation before dispatch, revalidate bindings,
  budgets and deadlines, use fresh attempts and writer worktrees, and never replay
  after restart. Cancellation/Stop are session/form/revision guarded.
- [x] Show waiting time and an accessible cancel action; preserve drafts/focus.
  Cover concurrent claims, stale controls, restart, exclusions and writer/final
  limits; run quality, update docs/AGENTS/README and merge local main.

Evidence: [worklog](../worklog/2026-10-21-R060j-provider-backoff.md). This does not
complete interrupted native/sleep recovery or live-provider acceptance.
