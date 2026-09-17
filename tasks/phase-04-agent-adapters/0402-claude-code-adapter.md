# 0402 — Implement Claude Code Adapter

## Objective

Integrate a pinned Claude Code CLI version: probe, headless invocation, permission mode and allowed tools from the grant, per-run instruction files and skills in the run's `agent/` folder, MCP servers from enabled plugins, structured output, usage, cancellation, native resume, and memory-directory handling that never writes the user's global auto memory..

## Dependencies

- 0401.

## Scope

Integrate a pinned Claude Code CLI version: probe, headless invocation, permission mode and allowed tools from the grant, per-run instruction files and skills in the run's `agent/` folder, MCP servers from enabled plugins, structured output, usage, cancellation, native resume, and memory-directory handling that never writes the user's global auto memory.

## Deliverables

- Adapter and supported-version declaration.
- Redacted fixtures and conformance results.
- Effective grant mapping documentation and known limitations.

## Checklist

- [ ] Revalidate current CLI flags and event schema.
- [ ] Constrain tools and paths to the grant; record what cannot be constrained.
- [ ] Keep runtime memory/config run-scoped or document the exact exception.
- [ ] Inject knowledge and record usage; parse citations.
- [ ] Test native resume and continuation fallback after a sleep gap.

## Acceptance criteria

- [ ] Passes conformance for supported versions.
- [ ] Auth failure blocks only Claude sessions.
- [ ] No secret canary in persisted output.
- [ ] Effective grant recorded on every session.

## Verification and evidence

Run fixture CI plus an opt-in budget-capped real CLI smoke covering success, tool denial, timeout, cancel, resume, and sleep gap.
