# R020h — Agent connection wizard and working model check

Status: complete, 2026-10-10.

- [x] Diagnose the real model-check failure and fix the shared adapter with bounded protocol regressions.
- [x] Replace the Agents setup wall with Choose Agent → Connect and Authorize → Select models → Save, keeping unsupported agents honest.
- [x] Keep execution consent explicit through clear actions, preserve existing private sign-in and immutable role bindings, and persist selected models with revision/idempotency/audit guards.
- [x] Show useful failure messages, keyboard-accessible navigation, cancellation and reconnect behavior.
- [x] Verify real connection/model behavior, unchanged-schema data preservation, focused/full tests, packaged app and desktop browser UI. Update docs, README and AGENTS; merge local main without publishing.

Evidence: [worklog](../worklog/2026-10-10-R020h-agent-wizard.md).

Deferred: separate narrow viewport run and broader real-provider/release acceptance; see worklog.
