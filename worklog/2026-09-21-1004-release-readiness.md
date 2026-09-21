# 1004 — MVP release readiness

Claimed on `fix/1004-resource-retention` from clean `main`. Task 1003 is
still in progress, so this is an independent preflight of one task-1004 gate,
not release acceptance. Acceptance for this tranche: automatic retention must
not delete measured resource samples while an active stage still needs them
for its durable stage aggregate; completed stages may be pruned only after
their aggregate exists; focused regression and quality checks pass; `docs/`
and `docs/PLAN.md` distinguish verified behavior from remaining beta gates.

Ponytail 4.10.0 (MIT, full mode), observability, security-review, and
quality-gates apply. XERJ project search was unavailable because the loopback
node on port 9200 is not running; inspected the source and tests directly.
The current `ResourceRollups.maintain/1` computes finished-stage rollups and
then deletes all samples older than seven days, including samples of an
unfinished long-running stage. Such a stage could later finish with a partial
aggregate. This is a local-data accuracy risk, not an outbound telemetry issue.

The change gates automatic raw deletion on an existing durable stage rollup,
using the existing stage/session relationship in a SQL subquery. It adds no
new table, worker, setting, or dependency. A focused regression holds one
stage open across eight days, confirms no sample is pruned, then finishes it
and confirms maintenance writes a full stage aggregate before deleting the
aged raw row. Direct stage aggregation now rejects unfinished stages as well,
so an incidental caller cannot create a provisional rollup that would make
those raw samples eligible for pruning. `rtk env -u CR_PAT mix test
test/cuckoding/telemetry/resource_metrics_test.exs` passed (5 tests, 0
failures). Static source inspection found no automatic product telemetry HTTP
client: local resource sampling writes SQLite; diagnostics export and shell
update checks are explicit user actions. That is code-level preflight only,
not outbound-network evidence from a signed enrollment build. Minute rollup
backfill after long downtime remains unproven, so the broad retention and
consent gate stays open in task 1004 and `docs/BETA_REPORT.md`.

Final checks: `rtk env -u CR_PAT mix format` passed;
`rtk env -u CR_PAT mix test
test/cuckoding/telemetry/resource_metrics_test.exs` passed again (5 tests,
0 failures) after the unfinished-stage guard. `rtk env -u CR_PAT mix quality`
passed (10 properties, 283 tests, 0 failures; Credo 0 issues; Sobelow scan
complete; Hex audit found no retired/advisory packages). The two
plugin-supervisor crash logs were intentional test fixtures. No migration,
external network operation, or user data deletion was performed by this
change. Residual risk: minute rollups missed during long app downtime are not
yet backfilled; stage totals remain protected by the new pruning guard.

## 2026-09-21 — Catch up missed minute rollups before pruning

Continued task 1004 on `fix/1004-minute-rollup-catchup` from clean `main`.
Acceptance for this tranche: maintenance finds completed minutes missed during
an app outage; work is bounded per tick and resumes from durable rows after
restart; raw samples cannot be pruned until both minute and finished-stage
aggregates exist; an eight-day synthetic outage and backlog regression pass;
and docs/PLAN report the resulting evidence without calling the signed beta
gate complete. No migration or provider operation is intended.

Ponytail 4.10.0 (MIT, full mode), observability, security-review, and
quality-gates apply. XERJ project search was unavailable on loopback port
9200; inspected `ResourceRollups.maintain/1`, `prune/2`, the current indexes,
and the focused tests directly. A read-only SQLite parameter probe was
insufficient to infer Ecto's column encoding; the focused fixture confirmed
stored UTC timestamps include `Z`, so catch-up uses that exact minute key for
indexed rollup lookup.

Implementation: maintenance queries missing completed session-minute buckets
against the existing unique rollup index, ordered oldest first with a limit
of 120 per tick. No process-local cursor or new table is needed: the next
tick/restart selects whatever durable buckets remain. Automatic raw pruning
now requires both the minute rollup and the finished-stage rollup, so a
failed or incomplete catch-up never destroys its source rows. The first
focused run exposed a timestamp-format mismatch in the SQL fragment; a
synthetic fixture showed the actual stored `Z` suffix, and the query was
corrected before acceptance. Tests cover an eight-day interruption, a
121-minute backlog across repeated maintenance calls, idempotent repeat
calls, and refusal to prune a finished-stage sample lacking its minute
rollup. Removed the unused `prune_raw/1` helper, which bypassed the safe
aggregate guard and was only called from one test. This is synthetic local
evidence, not a signed-build observation. The lookup can scan retained raw
rows; the 120-bucket cap bounds aggregation, not query cost. Profile that scan
with beta-sized data before raising throughput claims.

Verification: `rtk env -u CR_PAT mix format` passed;
`rtk env -u CR_PAT mix test
test/cuckoding/telemetry/resource_metrics_test.exs` passed (7 tests, 0
failures). `rtk env -u CR_PAT mix quality` passed (10 properties, 285 tests,
0 failures; Credo 0 issues, Sobelow scan complete, Hex audit found no
retired/advisory packages). Expected plugin-supervisor crash fixtures and
transient SQLite lock retries appeared in the suite output; no test failed.
`rtk git diff --check` passed. No migration, signed build, paid provider
invocation, or deletion of the user's existing app data was performed.
