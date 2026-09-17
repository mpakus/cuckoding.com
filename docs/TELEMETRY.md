# Telemetry, Metrics, and Cost Accounting

## Objectives

Telemetry must make work attributable, failures diagnosable, costs explainable, sleep gaps visible, plugin contributions measurable, and knowledge use observable. It must avoid false precision and unnecessary collection of sensitive content.

## Correlation model

`project_id → board_id → task_id → run_id → stage_attempt_id → agent_session_id`, plus adapter, runtime version, requested/actual model, environment ID, process ID, command ID, plugin keys, knowledge item IDs, and trace/span IDs.

## Metric classes

### Workflow

Queue time, stage active and wall duration, attempts, retries, waits by reason, approvals, blocked time, sleep gaps; tasks completed, failed, cancelled, hibernated, reopened; findings by severity/category and stage bounce count.

### Provider usage and cost

Input, output, reasoning when explicitly reported, cache-read, and cache-write tokens; request count, rate-limit time, provider-reported cost, currency; estimated cost using a versioned price catalog only when provider cost is absent; confidence/source: `provider_reported`, `catalog_estimate`, `unavailable`.

### Host resources

CPU time and percentage, RSS, process and thread count, open ports per process group; sampled every 2–5 seconds while active; aggregated to 1-minute and stage rollups. Hard limits are not enforced on the host runner and are never displayed as if they were.

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

## Cost calculation

1. Prefer provider-reported monetary cost.
2. Otherwise select the price catalog effective at request time.
3. Apply input/output/cache categories separately.
4. Record the formula, catalog version, currency, and rounding.
5. Show estimated values with an `≈` indicator and tooltip.
6. Never infer subscription-plan marginal cost as if it were API billing.

## Event pipeline

Workers emit structured internal telemetry. A redaction processor removes secrets and unsafe content. Durable business/audit events go to SQLite before PubSub. High-volume samples are batched. Optional OpenTelemetry export is disabled by default and must declare its destination and data classes.

## Retention and export

Raw sensitive logs use the shortest useful retention. Aggregates and audit facts use longer retention. Users can export redacted JSON/CSV bundles with schema version, timezone, price catalog version, confidence, and missing-data flags. Deletion and consolidation never rewrite original cost facts without an audit event.
