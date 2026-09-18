# Worklog — 0705 knowledge injection and usage

## Metadata

- Date/time (UTC): 2026-09-18
- Task: 0705
- Status: done
- Human/agent owner: codex
- Branch: `feature/0705-knowledge-injection`
- Start revision: `b518af7`
- End revision: pending

## Acceptance criteria

- Select the bounded project/global index and stage-triggered items for the next run.
- Render untrusted knowledge only inside the run-owned `agent/` directory using the runtime's native filename.
- Require a scoped capability token for on-demand retrieval and refuse cross-project access.
- Parse explicit citations and record injected, retrieved, cited, accepted, and contradicted usage with item versions.
- Complete E2E scenario 8 by recording usage in the next run after reviewed publication.

## Reference coding

- Focused project and Hydra XERJ searches were attempted first; the documented node at `localhost:9200` was unreachable, so retrieval degraded to direct pinned-source inspection.
- Verified pinned Hydra revision `d8ad56112c2c3acfb2f65f53b6890f30a25c693c` and its MIT license. `electron/agents/providers.ts:91-165` keeps provider-specific argv/session construction behind one provider contract; no peer knowledge-injection code was found or copied.
- Reused Cuckoding's existing adapter-owned renderers at `lib/cuckoding/adapters/codex.ex:57` and `lib/cuckoding/adapters/claude_code.ex:61`. The new domain service supplies only bounded, reviewed data and records usage after a successful render/start.
- Applied Ponytail full 4.10.0, `ponytail-minimalism`, `knowledge-compression`, `agent-adapter`, `security-review`, `elixir-phoenix-liveview`, `better-accessibility`, and `quality-gates`. The result adds no dependency or secondary retrieval service.

## Work performed

- Claimed task 0705 and restated its acceptance criteria.
- Added bounded project-index and stage/task-trigger selection over synchronized, hash-verified Markdown, with global knowledge gated by the run's trusted policy snapshot.
- Reused each adapter's run-owned native configuration and marked all supplied knowledge as untrusted evidence that cannot alter tools, permissions, or policy.
- Added short-lived hashed retrieval capabilities scoped to project/run/stage, bounded lexical retrieval, explicit versioned citations, and a JSON endpoint that never persists raw query text.
- Added append-only, idempotent usage facts for injected, retrieved, cited, accepted, and contradicted versions; retrieval audit and selected-item usage commit atomically.
- Linked candidate acceptance and later update/supersession to immutable outcomes.
- Added end-to-end coverage for publication into the next run, native Fake-adapter rendering, capability expiry, append-only enforcement, raw-query canaries, correction lineage, and cross-project refusal.
- Updated knowledge, database, adapter, security, testing, plan, and task documentation; closed the deferred 0704 scenario.

## Verification

- `rtk mix compile --warnings-as-errors` — passed.
- `rtk mix test test/cuckoding/knowledge/injection_test.exs test/cuckoding_web/knowledge_retrieval_controller_test.exs test/cuckoding/knowledge/publication_service_test.exs test/cuckoding/walking_skeleton_test.exs test/cuckoding/adapters/agent_adapter_test.exs test/cuckoding/adapters/codex_test.exs test/cuckoding/adapters/claude_code_test.exs` — passed: 29 tests, 0 failures.
- `rtk env MIX_ENV=test mix ecto.rollback --step 1 && rtk env MIX_ENV=test mix ecto.migrate` — passed; capability, retrieval, usage tables, indexes, and append-only triggers reverse and reapply cleanly.
- `rtk env MIX_ENV=test mix ecto.reset` — passed from an empty disposable test database through all migrations.
- `rtk mix test test/cuckoding/knowledge/injection_test.exs test/cuckoding_web/knowledge_retrieval_controller_test.exs` after migration reapply — passed: 3 tests, 0 failures.
- `rtk mix quality` — passed: formatter/dependency checks, warning-clean compiler, 10 properties and 155 tests with 0 failures, Credo over 134 source files with no issues, Sobelow clean, and Hex audit with no retired or advisory packages.
- `rtk git diff --check` — passed before commit.

## Handoff

Complete pending the task commit and fast-forward merge to local `main`.
