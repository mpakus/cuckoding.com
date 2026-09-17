# 0402 — Implement Claude Code Adapter

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0402-claude-code-adapter.md
```

## Objective

Integrate a pinned Claude Code CLI version: probe, headless invocation, permission mode and allowed tools from the grant, per-run instruction files and skills in the run's `agent/` folder, MCP servers from enabled plugins, structured output, usage, cancellation, native resume, and memory-directory handling that never writes the user's global auto memory.

## Dependencies

- 0401.

## Scope

Integrate a pinned Claude Code CLI version: probe, headless invocation, permission mode and allowed tools from the grant, per-run instruction files and skills in the run's `agent/` folder, MCP servers from enabled plugins, structured output, usage, cancellation, native resume, and memory-directory handling that never writes the user's global auto memory.

## Deliverables

- Adapter and supported-version declaration.
- Redacted fixtures and conformance results.
- Effective grant mapping documentation and known limitations.

## Checklist

- [x] Revalidate current CLI flags and event schema.
- [x] Constrain tools and paths to the grant; record what cannot be constrained.
- [x] Keep runtime memory/config run-scoped or document the exact exception.
- [x] Inject knowledge and record usage; parse citations.
- [x] Test native resume and continuation fallback after a sleep gap.

## Acceptance criteria

- [x] Passes conformance for supported versions.
- [x] Auth failure blocks only Claude sessions.
- [x] No secret canary in persisted output.
- [x] Effective grant recorded on every session.

## Verification and evidence

Run fixture CI plus an opt-in budget-capped real CLI smoke covering success, tool denial, timeout, cancel, resume, and sleep gap.

Evidence: the pinned `2.1.142` fixture conformance suite passes all 4 focused tests and the full repository gate passes 8 properties plus 79 tests. The installed CLI/version and global/scoped authentication probes were revalidated. The real provider smoke was not run because this machine has global OAuth only, while the required isolated `--bare` mode intentionally excludes OAuth/Keychain login; the adapter reports this as `run_scoped_auth_required` instead of exposing the user's home or copying credentials. See the linked worklog for exact commands and limitations.
