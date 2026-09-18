# 0705 — Knowledge Injection into Runtimes and Usage Tracking

## Objective

Implement selection of always-injected index and triggered items per stage, rendering into runtime-native files in the run's `agent/` folder, the on-demand retrieval endpoint, citation parsing, and `knowledge_usages` records for injected/retrieved/cited/accepted/contradicted..

```yaml
status: done
owner: codex
started_at: 2026-09-18
worklog: worklog/2026-09-18-0705-knowledge-injection.md
```

## Dependencies

- 0704.
- 0402 or 0403.

## Scope

Implement selection of always-injected index and triggered items per stage, rendering into runtime-native files in the run's `agent/` folder, the on-demand retrieval endpoint, citation parsing, and `knowledge_usages` records for injected/retrieved/cited/accepted/contradicted.

## Deliverables

- Injection selector and renderers per adapter.
- Retrieval endpoint with capability token.
- Usage recorder and outcome linker.

## Checklist

- [x] Never write the user's global runtime configuration.
- [x] Injected content marked untrusted.
- [x] Every injection has a usage record.

## Acceptance criteria

- [x] Next run after publication records usage.
- [x] Reviewer acceptance and later corrections update outcomes.

## Verification and evidence

Run injection, endpoint, and usage tests with the fake adapter.
