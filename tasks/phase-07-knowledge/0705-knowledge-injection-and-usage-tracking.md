# 0705 — Knowledge Injection into Runtimes and Usage Tracking

## Objective

Implement selection of always-injected index and triggered items per stage, rendering into runtime-native files in the run's `agent/` folder, the on-demand retrieval endpoint, citation parsing, and `knowledge_usages` records for injected/retrieved/cited/accepted/contradicted..

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

- [ ] Never write the user's global runtime configuration.
- [ ] Injected content marked untrusted.
- [ ] Every injection has a usage record.

## Acceptance criteria

- [ ] Next run after publication records usage.
- [ ] Reviewer acceptance and later corrections update outcomes.

## Verification and evidence

Run injection, endpoint, and usage tests with the fake adapter.
