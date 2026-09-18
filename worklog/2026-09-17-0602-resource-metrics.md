# Worklog — 0602 host resource metrics and rollups

## Metadata

- Date/time (UTC): 2026-09-17
- Task: 0602
- Status: complete
- Human/agent owner: codex
- Branch: `feature/0602-resource-metrics`
- Start revision: `39bc6f0`
- End revision: pending commit

## Acceptance criteria

- Sample CPU time, RSS, process count, and listening ports for the recorded process group every 2–5 seconds.
- Attribute samples to the correct durable process and agent session; never inspect or attribute an unverified/reused process identity.
- Produce one-minute and stage rollups from measured rows only, keep active and wall time distinct, and never interpolate missing samples.
- Mark host-runner limits as unenforced and provide bounded raw-sample retention.

## Reference coding

- Focused project and pinned Hydra XERJ searches were attempted first; the configured node at `127.0.0.1:9200` was unreachable, so retrieval is degraded.
- Inspected the project process-identity boundary in `lib/cuckoding/execution/local_process_runner.ex` and pinned Hydra revision `d8ad56112c2c3acfb2f65f53b6890f30a25c693c` under MIT. Hydra had no equivalent process-resource implementation to adapt.
- Reused the existing PID/start-identity and process-group ownership boundary. Cuckoding's sampling, measured-only rollups, active/wall timing, and unenforced-limit labeling are independent implementations; no peer code was copied.

## Work performed

- Claimed task 0602 and restated its acceptance criteria.
- Added replaceable resource-collector and supervised sampler boundaries with a configurable 3-second production interval and explicit test disablement.
- Extended the local host inspector to verify the recorded process identity before measuring cumulative CPU, RSS, process count, and owned listening ports.
- Added durable resource samples attributed to both the process and agent session; missing or exited processes intentionally produce no measurement row.
- Added idempotent minute and stage rollups with measured CPU deltas, memory and process aggregates, port unions, and separate durable active/wall timing.
- Added minute maintenance for completed-minute and newly finished-stage rollups, seven-day raw retention, 30-day rollup retention, and database constraints for non-negative measurements and valid timing.
- Updated architecture, database, telemetry, development, and implementation-plan documentation.

## Verification

- `rtk mix test test/cuckoding/telemetry/resource_metrics_test.exs test/cuckoding/execution/local_process_runner_test.exs` — passed: 12 tests, 0 failures. Covers exact process/session attribution, missing samples, 2–5 second configuration, real loopback listener discovery, automatic completed-minute/final-stage maintenance, minute normalization, stage timing, repeat-safe rollups, and retention.
- `rtk mix compile --warnings-as-errors` — passed.
- An initial full gate surfaced the sampler querying after Ecto sandbox ownership ended. The sampler is now disabled through application configuration in tests and has an explicit opt-out regression test; the production default remains enabled at 3 seconds.
- Final `rtk mix quality` — passed: formatter check; compiler with warnings as errors; 10 properties and 122 tests with 0 failures; Credo strict over 104 source files and 1,430 modules/functions with no issues; Sobelow clean; Hex audit found no retired or advisory packages. No background ownership error remained.
- `rtk git diff --check` — passed before commit.

## Handoff

Complete. Raw gaps remain gaps; rollups never infer measurements, and the host runner never claims to enforce CPU or memory limits.
