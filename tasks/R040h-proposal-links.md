# R040h — Speculator prerequisites and source citations

Status: complete; verified and merged into local main at `ffe58e9`. Owner: Codex.

- Version the planning response contract. New proposals include prerequisite
  indices and selected-document indices; existing v1 receipts remain unchanged.
- Require 1–6 tasks in prerequisite-first order. References are distinct bounded
  integers: prerequisites point only to earlier tasks, citations only to document
  snapshots actually sent with this request. Reject malformed, self, forward,
  cyclic, foreign and downgraded responses before retaining proposal text.
- Show prerequisite names and exact cited snapshots. Import only after required
  proposals are imported; resolve their current same-board UUIDs inside the
  existing transaction. Never duplicate imports or overwrite edited prerequisites.
- Preserve original source linkage on imported tasks and expose citations in their
  editor. Manual edits cannot silently replace original source provenance.
- Preserve old receipts, command idempotency, event atomicity, cancellation,
  session boundaries and unsaved forms. No new migration, runtime permission,
  file access, provider login or execution authority.
- Verify Elixir/native contracts, malformed output, import rollback, legacy
  compatibility, LiveView/reconnect and packaged fixture/restart behavior. Update
  docs/AGENTS/README, merge local main and delete the feature branch.

This validates reference scope and ordering, not the semantic truth of a citation
or an accepted specification. Real-provider acceptance and battles remain open.

Evidence: [worklog](../worklog/2026-10-07-R040h-proposal-links.md).
