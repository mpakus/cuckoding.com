# Worklog — 0702 per-run knowledge extraction

## Metadata

- Date/time (UTC): 2026-09-17
- Task: 0702
- Status: complete
- Human/agent owner: codex
- Branch: `feature/0702-knowledge-extraction`
- Start revision: `7eae987`
- End revision: pending commit

## Acceptance criteria

- Build bounded extraction input only from durable public events and public artifact descriptors.
- Redact registered secrets and sensitive keyed fields before runtime synthesis and again before candidate persistence.
- Use the completed run's recorded runtime session under the trusted project policy.
- Classify exact duplicates as `noop`, same-item revisions as `update`, explicit valid replacements as `supersede`, and new knowledge as `add`.
- Persist every candidate with run/event/artifact/repository evidence IDs; never trust model-supplied provenance.

## Reference coding

- Focused project, Agetor, and Vibe Kanban XERJ searches were attempted first; the configured node at `127.0.0.1:9200` was unreachable, so retrieval is degraded.
- Direct pinned-source inspection found no peer knowledge-extraction pipeline to adapt.

## Work performed

- Claimed task 0702 and restated its acceptance criteria.
- Added durable, constrained extraction jobs and candidate review rows with one job per run and atomic candidate persistence.
- Added a fixed-template extractor gated by completed-run state and trusted `knowledge.extraction` policy, using the latest durable runtime session recorded for that run.
- Built bounded inputs from normalized public activity and artifact event descriptors only; raw artifact files, provider payloads, hidden reasoning, and model-proposed evidence never enter the pipeline.
- Applied registered-value and sensitive-key redaction before adapter synthesis and after untrusted structured output.
- Computed exact duplicate `noop`, same-kind/title `update`, valid explicit `supersede`, and new-item `add` operations against scope-checked project knowledge.
- Assigned run, event, artifact-event, and repository SHA evidence from trusted durable rows to every candidate.
- Made completed extraction idempotent and failures durable without partial candidate rows or persisted error details.
- Extended the deterministic fake adapter with an optional structured reply while preserving its existing default behavior.
- Updated architecture, knowledge, reference-coding, and implementation-plan documentation.

## Verification

- Final `rtk env MIX_ENV=test mix ecto.reset` — passed after database-constraint tightening; every migration including extraction applied from an empty disposable test database.
- `rtk mix test test/cuckoding/knowledge/extractor_test.exs` — passed: 3 tests, 0 failures. Covers all four operations, exact target attribution, double-redaction canary removal, trusted evidence IDs, completed-job replay, policy/state refusal, durable failure, and no partial candidates.
- `rtk mix credo --strict` — passed over 122 source files and 1,736 modules/functions after simplifying transaction persistence.
- Final `rtk mix quality` — passed: formatter check; compiler with warnings as errors; 10 properties and 142 tests with 0 failures; Credo over 122 source files and 1,736 modules/functions with no issues; Sobelow clean; Hex audit found no retired or advisory packages.
- `rtk git diff --check` — passed before commit.

## Handoff

Complete. Extraction remains bounded, policy-gated, redacted, project-scoped, evidence-backed, and review-only.
