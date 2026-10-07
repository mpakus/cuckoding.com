# R030b — Adopt saved teams in existing scopes

Status: verified; local main integration pending. Owner: Codex.

- Preview the current and latest saved default team in an Arena or Tabula;
  explicitly confirm adoption, including changed/removed roles and instructions.
- Arena adoption affects subsequently created boards only. Tabula adoption
  affects future planning requests only. Preserve creation references, previous
  adoptions, existing drafts and every earlier planning receipt.
- Persist adoption and audit event atomically with idempotent command keys;
  reject stale scope/default revisions, foreign boards and active board planning.
- Clear stale planning/adoption consent without losing entered text. A saved
  binding never grants execution or bypasses current provider/model checks.
- Cover domain and LiveView behavior, fresh/prior-schema migration, isolated
  packaged browser/restart, and documentation. Merge verified local main and
  delete the merged branch; no remote publication.

This adopts a saved default revision. Per-scope role editing, custom execution
slots/grants and battles remain separate work.
