# R101 — Decimal advisory

Status: complete, 2026-10-13. Branch: `fix/R101-decimal-security`.

- [x] Upgrade only Decimal to a compatible patched version.
- [x] Verify dependency audit, quality and production compilation.
- [x] Update documentation and merge into local main.

No application caller uses Decimal directly; Ecto/SQLite/Jason require it.
No database migration or new dependency is needed.
