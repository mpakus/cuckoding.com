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

Workers emit structured internal telemetry. A redaction processor removes secrets and unsafe content. Durable business/audit events go to SQLite before PubSub. High-volume samples are batched. Optional OpenTelemetry export is disabled by default and must declare its destination and data classes.

## Retention and export

Raw sensitive logs use the shortest useful retention. Aggregates and audit facts use longer retention. Users can export redacted JSON/CSV bundles with schema version, timezone, price catalog version, confidence, and missing-data flags. Deletion and consolidation never rewrite original cost facts without an audit event.
