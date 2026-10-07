# R040e — Speculator proposals from a brief

Status: complete on local main. Owner: Codex. Implementation: `c01bdab`.
Merged feature branch deleted; no remote publication.

- Use the Tabula's frozen Speculator/Codex/model binding, a fresh verified
  connection and explicit consent to send a bounded brief and saved instructions.
- Run one ephemeral structured turn using the existing no-tools, empty scratch
  grant. Never read the Arena, run delivery work or infer new permissions.
- Validate a bounded public summary and up to six unique task proposals. Persist
  the request, binding and completion receipt; omit raw provider output/reasoning.
- Show state, owner/runtime/model, elapsed time and cancellation. Preserve typed
  text across updates, retain results across reconnect, and never replay an
  interrupted turn automatically.
- Let users import proposals individually into Specs once, preserving provenance
  and ordinary draft revision/editing semantics. Reject foreign/stale scope.
- Add focused domain, transport and LiveView coverage; verify the isolated native
  bundle and browser. Update docs, README and AGENTS; merge local main and delete
  the merged branch. Separate fixtures from real-account acceptance.

Limits: brief-only, required Speculator, six proposals, no file-backed specs,
dependencies, custom planning-role selection or battle execution in this slice.
