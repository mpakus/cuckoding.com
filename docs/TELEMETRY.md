# Telemetry, Metrics, and Cost Accounting

## Objectives

Telemetry must make work attributable, failures diagnosable, costs explainable, sleep gaps visible, plugin contributions measurable, and knowledge use observable. It must avoid false precision and unnecessary collection of sensitive content.

## Correlation model

`project_id → board_id → task_id → run_id → stage_attempt_id → agent_session_id`, plus adapter, runtime version, requested/actual model, environment ID, process ID, command ID, plugin keys, knowledge item IDs, and trace/span IDs.

For board batches, `runs.board_execution_id` links controller and delivery runs
to one execution. Board events carry the execution ID and revision in the
existing `board:<id>` stream. Membership is counted separately from attempts.

## Metric classes

### Workflow

Queue time, stage active and wall duration, attempts, retries, waits by reason, approvals, blocked time, sleep gaps; tasks completed, failed, cancelled, hibernated, reopened; findings by severity/category and stage bounce count.

### Provider usage and cost

Input, output, reasoning when explicitly reported, cache-read, and cache-write tokens; request count, rate-limit time, provider-reported cost, currency; estimated cost using a versioned price catalog only when provider cost is absent; confidence/source: `provider_reported`, `catalog_estimate`, `unavailable`.

Delivery and planning runs scan their bounded, redacted provider JSONL after each process exits and before the stage advances. Terminal Codex, Claude Code, and Cursor Agent usage is normalized through the adapter and stored once per session/event; a failed process can still report usage. Missing usage remains unavailable. Malformed usage leaves a safe `agent.usage_unavailable` event, not an invented total or raw provider payload. Historical logs are not automatically replayed by this change.

The accounting path hashes the provider event key for idempotent agent-session attribution and keeps usage provenance separate from cost provenance. Provider-reported monetary cost always wins. When it is absent, only an explicitly declared `api` billing mode may use the immutable catalog effective at the usage timestamp; `subscription` and `unknown` remain unavailable. Missing model rates make the entire estimate unavailable rather than partially pricing it. The status dashboard renders provider values without a prefix, catalog estimates with `≈`, and unavailable cost as text.

### Host resources

CPU time and percentage, RSS, process and thread count, open ports per process group; sampled every 2–5 seconds while active; aggregated to 1-minute and stage rollups. Hard limits are not enforced on the host runner and are never displayed as if they were.

The implemented host sampler uses a three-second default and accepts only intervals from two through five seconds. Before every read it verifies the recorded root PID and start identity, then attributes the owned group to the process row's agent session. A missing, exited, mismatched, or uninspectable group produces no sample. Maintenance catches up to 120 missing completed session-minutes per tick from durable rows and writes newly finished-stage rollups before pruning. A raw sample older than seven days is deleted only after both its minute and finished-stage rollups exist; rollups are eligible after 30 days. Minute rollups expose sample count and measured resource aggregates but leave active/wall duration unavailable; stage rollups use the attempt's separately persisted `active_ms` and `wall_ms`. Neither path fills gaps or treats absent rows as zero.

### Plugins and caches

Separate dimensions; never summed into one number:

| Kind | Primary measures | Interpretation |
| --- | --- | --- |
| Shell filter (RTK) | raw bytes, compact bytes, estimated tokens, commands filtered, coverage ratio | Estimated context reduction |
| Knowledge backend | query count, hit count, selected results, context bytes, latency | Retrieval activity; avoided tokens are estimates |
| Provider prompt cache | cache read/write tokens and pricing fields | Provider-reported |
| Dependency/build caches | hits/misses, bytes, time | Acceleration, reported by declared commands where available |

### Knowledge

Items by kind/status over time, candidates per run, approval rate, injected/retrieved/cited counts per stage, acceptance rate of stages that used an item, contradiction rate, stale-item rate, consolidation job stats.

### Power

Assertion time, sleep gaps per run, reconciliation outcomes (continued, resumed, recovered, blocked).

### Board batch accounting

`BoardControl.Statistics` queries all available records linked to the batch,
including every retry and controller session. It does not derive totals from
Agent Floor's 100-session or 50-operation display windows.

| Measure | Current calculation and limit |
| --- | --- |
| Progress | One count per membership: pending, active, done, blocked, skipped or deferred; neither skipped nor deferred means completed |
| Attempts and reviews | Retained runs and stage/session history; Review attempts after the first count as returns |
| Time | Clock-elapsed batch wall time, persisted stage active time, board pause intervals and recorded machine sleep gaps; active work may be partial and sleep may overlap pause |
| Tokens | Each reported dimension summed separately, with session coverage; cache/reasoning dimensions are not added into a fabricated total |
| Cost | Integer micros grouped by currency and provider-reported/catalog-estimate source; missing measurements remain unavailable |
| Resources | CPU deltas between retained samples, largest sampled process-tree memory, latest sampled active memory, owned process groups and observed ports; timestamp and coverage expose partial/stale observations |

Raw resource samples still follow the retention rules above. This batch view
does not reconstruct pruned samples from metric rollups, so complete membership
coverage is not a promise of complete lifetime resource telemetry. No samples
means unavailable. The panel exposes the recorded controller decision count and
cap; it does not predict remaining spend or time. See
[CUCKODING-CONTROL.md](CUCKODING-CONTROL.md).

## Cost calculation

1. Prefer provider-reported monetary cost.
2. Otherwise select the price catalog effective at request time.
3. Apply input/output/cache categories separately.
4. Sum integer `tokens × micros-per-million` numerators, divide once by `1,000,000`, and round to the nearest micro with halves up. The reconciliation error is therefore at most half a micro before the integer result.
5. Record every formula dimension, total numerator, denominator, rounding rule, catalog version, and currency.
6. Show estimated values with an `≈` indicator and explicit source label.
7. Never infer subscription-plan marginal cost as if it were API billing.

Plugin optimization claims record raw, optimized, and saved units with their own source, confidence, method, and metadata. They are not subtracted from provider token counts or monetary cost.

## Event pipeline

Workers emit structured internal telemetry. Redaction removes secrets and unsafe
content before persistence. Durable business/audit events go to SQLite before
PubSub. Samples and rollups are local. An optional OpenTelemetry exporter is a
future extension; no outbound exporter is configured by the current source.

## Retention and export

Raw resource samples and rollups have the age/coverage pruning described above.
Full redacted process artifacts and diagnostic payload fragments have no automatic
age purge. Original usage/cost and audit facts are retained; never infer a 30-day
log deletion policy from the metrics retention window. See [DB.md](DB.md#retention).

The implemented diagnostics export is an explicit, allowlisted local support
bundle, not a general metrics export. Schema-versioned JSON/CSV telemetry export
with price-catalog, confidence and missing-data fields remains a design target.
There is no automatic outbound product analytics or crash-report upload.
