# 0403 — Implement Codex Adapter

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

- [ ] Revalidate CLI flags and event schema.
- [ ] Map grant to approval and sandbox modes; record effective grant.
- [ ] Inject knowledge and record usage.
- [ ] Test cancel, resume, and sleep-gap recovery.

## Acceptance criteria

- [ ] Passes conformance.
- [ ] Auth failure blocks only Codex sessions.
- [ ] No secret canary in output.

## Verification and evidence

Fixture CI plus opt-in real CLI smoke.
