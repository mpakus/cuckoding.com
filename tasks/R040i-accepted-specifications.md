# R040i — Accepted Markdown specifications

Status: complete; implemented, verified and merged to local main (`40061ef`). Owner: Codex.

- Preview a saved task as bounded, readable Markdown with its exact task revision,
  prerequisite revisions and original cited snapshots. Require nonempty description
  and criteria; refuse foreign or stale tasks and unsaved editor changes.
- Explicit acceptance freezes that preview in a durable command before writing an
  app-owned private `.md` artifact. Never write into the Arena or overwrite files.
- Verify file bytes/hash before recording acceptance and moving the task to ToDo
  in the same transaction as immutable draft history and the audit event. Reject
  stale, cancelled, expired or malformed completions; never replay uncertain writes.
- Preserve original artifacts/history after edits; show when task/prerequisite
  revisions differ. Hash-check downloads and refuse missing/changed/unsafe files.
- Provide keyboard controls, elapsed state/cancel, session-protected downloads,
  retained input/disclosures, and restart recovery. Acceptance grants no execution.
- Verify focused domain/storage/LiveView/security cases, packaged fresh/prior data
  and browser/restart behavior. Update docs, AGENTS and README, then merge local
  main and remove the feature branch. Real-provider/battle gates remain open.

Evidence: [worklog](../worklog/2026-10-07-R040i-accepted-specifications.md).
