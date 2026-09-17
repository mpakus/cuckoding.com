# 0403 — Implement Codex Adapter

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0403-codex-adapter.md
```

## Objective

Integrate a pinned Codex CLI version with the same contract: probe, non-interactive invocation, approval/sandbox mode mapping (record when the runtime's own sandbox is active), event stream normalization, session identifiers, usage, cancellation, resume, knowledge injection via `AGENTS.md` fragments in the run folder..

## Dependencies

- 0401.

## Scope

Integrate a pinned Codex CLI version with the same contract: probe, non-interactive invocation, approval/sandbox mode mapping (record when the runtime's own sandbox is active), event stream normalization, session identifiers, usage, cancellation, resume, knowledge injection via `AGENTS.md` fragments in the run folder.

## Deliverables

- Adapter and supported-version declaration.
- Fixtures and conformance results.
- Grant mapping and limitations.

## Checklist

- [x] Revalidate CLI flags and event schema.
- [x] Map grant to approval and sandbox modes; record effective grant.
- [x] Inject knowledge and record usage.
- [x] Test cancel, resume, and sleep-gap recovery.

## Acceptance criteria

- [x] Passes conformance.
- [x] Auth failure blocks only Codex sessions.
- [x] No secret canary in output.

## Verification and evidence

Fixture CI plus opt-in real CLI smoke.

Evidence: the pinned `0.146.0` fixture suite passes all 5 focused tests and the full repository gate passes 8 properties plus 84 tests. The installed CLI, JSONL/resume flags, strict run configuration, global/scoped authentication separation, and observed error-event shape were revalidated. A successful real provider smoke was not run because the run-scoped `CODEX_HOME` is unauthenticated; the adapter reports `run_scoped_auth_required` instead of copying the global ChatGPT credential store. See the linked worklog for exact commands and limitations.
