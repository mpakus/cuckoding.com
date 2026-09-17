# Worklog — 0401 Agent adapter contract and fake

## Acceptance criteria

- Workflow-facing code uses only the adapter behaviour and shared typed values.
- Unknown or malformed provider events fail closed as untrusted input.
- Requested and actual models remain separate; absent model and usage facts remain explicitly unavailable.
- The fake adapter covers cancellation, native resume, continuation fallback, sleep-gap recovery, redaction, and controlled failures.

## Reference coding

- Project XERJ search: `agent adapter contract capability probe normalized event usage effective grant fake adapter`.
- The repository runtime spike records an explicit permission grant and sandbox hash before launch at `spikes/0002-host-runtime/host_runtime_spike.rb:90-136`; the shared request therefore carries both requested and effective grants.
- Pinned Hydra MIT search: `agent manager capability session resume cancel event usage model process`. It confirmed persisted session IDs and native resume as provider boundaries; no shared contract code was copied.

## Verification

| Check | Result |
| --- | --- |
| `rtk mix test test/cuckoding/adapters/agent_adapter_test.exs` | Pass: 4 tests, 0 failures. |
| `rtk mix quality` (initial) | Functional suite passed: 8 properties, 75 tests. Strict Credo identified only new-module readability/refactoring findings; all were corrected before the final run. |
| `rtk mix quality` (final) | Pass: 8 properties, 75 tests, 0 failures; warnings-as-errors compilation, strict Credo with no findings, Sobelow, and dependency audit passed. |
| `rtk git diff --check` | Pass. |
| XERJ generation 22 dry-run / refresh | Dry-run passed and found the sealed generation pending replay. Replay aborted with HTTP 429 because disk usage is 99% and the node correctly kept the index read-only above its 95% flood-stage watermark. Generation 21 remains the last committed manifest; no disk-safety setting was weakened. |

## Work performed

- Added the complete provider-neutral adapter behaviour and shared typed request, capability, session, event, usage, continuation, grant, and error values.
- Added deterministic event ordering and deduplication; malformed or unknown events fail closed, and accepted summaries and metadata are recursively redacted and marked untrusted.
- Added a fake adapter with controlled failures, honest capability and unavailable-value reporting, native resume, bounded continuation fallback, sleep-gap recovery, cancellation, and usage collection.
- Generated only a mode-`0600` per-run fake configuration containing the effective grant, knowledge set, plugin set, and required output schema; a symlinked `agent/` directory is rejected.
- Persisted observed session identity, actual model, state, and the requested/enforced/unenforced grant without overwriting the requested model.
- Appended the effective-grant audit event in the same transaction as the session observation; its public payload lists grant field names without path or policy values.
- Covered normal workflow, timeout/cancel controls, reorder/duplicate events, unknown and malformed output, secret canary redaction, knowledge citation, recovery, continuation size bounds, config confinement, unavailable usage/model, and database observation.

## Security review

- Assets and boundary: provider output, generated runtime configuration, capability grants, model identity, usage, and session identifiers cross from an untrusted host process into the trusted workflow/database boundary.
- External provider events are accepted only as maps matching the closed public vocabulary; malformed values and hidden-reasoning event types return non-retryable errors, and accepted summaries/metadata are redacted before persistence.
- The adapter creates no capability: it maps the requested grant into explicit `enforced` and `unenforced` sections, writes only below the recorded run's `agent/` directory, and rejects an existing symlink at that boundary.
- The audit event contains only session identity and sorted grant field names; full path and policy values remain in the access-controlled session projection.
- Residual risk remains the documented trusted-host limitation: provider runtimes execute as user-owned host processes, and each real adapter must prove its own permission/config mapping and pass the conformance suite.
