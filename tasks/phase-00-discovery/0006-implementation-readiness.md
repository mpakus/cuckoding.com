# 0006 — Implementation Readiness

```yaml
status: done
owner: codex-01a0ad73-9f18-7ad1-8842-e5e0f041d160
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0006-implementation-readiness.md
```

## Objective

Turn the reviewed planning pack into a correctly placed, reproducible implementation baseline without restoring v1 or starting Phase 1 before the Phase 0 evidence gates pass.

## Dependencies

- 0005.

## Scope

Inspect the tracked clean-slate repository and deleted-v1 boundary, promote repository skills and example Cuckoding configuration to their documented root paths, validate the local implementation toolchain and configuration syntax, and record the exact Phase 0 execution order, blockers, and Phase 1 entry gate. Do not scaffold Phoenix, restore v1 code, select unresolved product decisions, enable plugins, or run destructive system/sleep tests.

## Deliverables

- Root `.agents/skills/` and `.cuckoding/` packs with no duplicate nested copies.
- Implementation-readiness report covering repository state, local toolchain, dependency order, entry gates, and residual decisions.
- Updated audit/readme references reflecting the resolved pack placement.
- Worklog containing exact verification and the next executable task.

## Checklist

- [x] Preserve the deliberate v1 deletion and avoid copying old implementation code forward.
- [x] Move, rather than duplicate, `.agents/` and `.cuckoding/` to the repository root.
- [x] Validate all YAML and local skill front matter after relocation.
- [x] Record installed/missing toolchain components without labeling an unexecuted install as complete.
- [x] Keep the unlicensed inspiration image untracked and outside implementation inputs.
- [x] Identify the single next task and the Phase 1 entry gate.

## Acceptance criteria

- [x] Root instructions resolve every required repository skill and example configuration path.
- [x] A new contributor can distinguish ready tooling from missing tooling and product decisions.
- [x] Phase 1 remains blocked until tasks 0001–0004 have accepted evidence.
- [x] No implementation source, dependency, secret, plugin activation, or external publication is introduced.

## Verification and evidence

Record path, YAML, tool-version, task-structure, Git-diff, and XERJ refresh evidence in `worklog/2026-09-17-0006-implementation-readiness.md`.
