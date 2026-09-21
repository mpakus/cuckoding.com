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
