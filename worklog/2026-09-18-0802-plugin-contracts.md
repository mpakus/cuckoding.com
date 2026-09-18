# Worklog — 0802 plugin kind contracts and conformance

## Metadata

- Date/time (UTC): 2026-09-18
- Task: 0802
- Status: complete
- Human/agent owner: codex
- Branch: `feature/0802-plugin-contracts`
- Start revision: `dd5e4df`
- End revision: task commit

## Acceptance criteria

- Define one explicit behaviour for every supported plugin kind.
- Provide a deterministic fake and reusable conformance coverage for every kind.
- Treat all plugin output as untrusted and require a source label on numbers.
- Scope short-lived capability tokens to the exact run, plugin, permissions, and network grant.
- Document the adapter, runner, knowledge, telemetry, VCS, secret, and notifier integration points.

## Reference coding

- Focused project, Vibe Kanban, and Agetor XERJ searches were attempted first;
  the configured loopback node was unavailable.
- Vibe Kanban revision `735654971bd396aa97b65166955678e4c34f8bf8` is
  Apache-2.0 licensed. Its shared executor trait at
  `crates/executors/src/executors/mod.rs:222-285` and QA fake at
  `crates/executors/src/executors/qa_mock.rs:1-85` informed the explicit
  contract plus deterministic-fake testing pattern; no source was copied.
- Agetor revision `eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a` is MIT
  licensed. Its observable fake driver at `src/bun/agents.ts:1109-1165`
  informed recording fake calls for assertions; no source was copied.
- Cuckoding adds closed result envelopes, recursive redaction, source-labeled
  measurements, and signed run/plugin/grant capability validation.

## Work performed

- Claimed Task 0802 and restated its acceptance criteria.
- Added explicit behaviours and closed operations for all nine plugin kinds.
- Added capability issuance and verification against the current durable
  activation, including run, optional stage/role, permission, and network scope.
- Added a bounded, recursively redacted result envelope that refuses unlabeled
  numbers and hides secret-store private values from inspection.
- Added deterministic fakes and a reusable conformance checker for every kind.
- Exposed capability issuance and guarded invocation through the Plugins
  context and documented the adapter, runner, knowledge, telemetry, VCS,
  secret-store, and notifier integration points.

## Verification

| Check | Result |
| --- | --- |
| `rtk mix test test/cuckoding/plugins/contracts_test.exs` | pass; 6 tests, 0 failures |
| `rtk mix credo --strict` | first run found one nested activation lookup; flattened before the final run |
| `rtk mix quality` | pass; 10 properties and 170 tests, 0 failures; Credo checked 154 files/2,351 functions and macros with no issues; Sobelow and dependency audit passed |
| `rtk git diff --check` | pass |

## Handoff

Task complete after the final diff check and local-main merge. Reference plugin
implementations remain Task 0803; this task supplies their guarded contracts,
deterministic fakes, and reusable conformance boundary.
