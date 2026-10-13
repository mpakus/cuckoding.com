# R101 — Decimal advisory

Ponytail full 5.2.0 (MIT), security-review and quality-gates apply. RTK prefixes
all commands; proxy preserves exact source and script output.

The [upstream advisory](https://github.com/ericmj/decimal/security/advisories/GHSA-6c27-994x-c52f)
identifies Decimal <3.1.2 as vulnerable to allocation from unbounded rounding
precision. The existing lock is 3.1.1; Ecto/SQLite accept the 3.x patch. Source
search found no direct application Decimal callers. Upgrade the existing
transitive dependency only, keeping the same schema and integer-based accounting.

## Verification

- `rtk mix deps.update decimal`: only Decimal changed, 3.1.1 → 3.2.0.
- `rtk mix quality`: 205 tests passed, compile/format/Credo/Sobelow/audit passed.
  Existing dependency compiler and quoted-keyword lock warnings remain.
- `rtk proxy env MIX_ENV=prod mix compile --warnings-as-errors`: passed.
- `rtk git diff --check`: passed. Local main integration only; no publication.

The running bundle still contains the prior dependency until the next packaged
rebuild. No database migration, native-code change or new application test is
needed for this compatible lock update. Native rebuild/smoke follows with execution
work; a successful source check alone does not update a running app.
