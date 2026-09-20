# 1020 — Review rerouting and local completion

## Metadata

- Date/time (UTC): 2026-09-20
- Task: 1020
- Status: done
- Human/agent owner: codex
- Branch: `feature/1020-review-reroute-local-completion`
- Start revision: `cb81c48`
- End revision: task commit on this branch; see Git history
- Environment and relevant tool versions: local macOS development environment

## Intended outcome

Connect validated Review findings to bounded Specifications or Coding reruns,
then let the human either release the reviewed branch or complete the task
locally without a push.

## Context inspected

- Required product, architecture, database, flow, security, execution, reference-coding, and Phase 10 planning documents.
- `WalkingSkeleton`, `GuidedRun`, workflow definition/evaluator, durable transitions, adapter output parser, Agent Floor, and Run LiveView.
- Dirty worktree contained only unrelated untracked `icon.png`; it is preserved.
- Ponytail 4.10.0 full, workflow-and-kanban, Phoenix LiveView, architecture, security-review, and quality-gates skills.
- XERJ search failed because no node was reachable at `localhost:9200`.
- Direct fallback: pinned `vibe-kanban@735654971bd396aa97b65166955678e4c34f8bf8`, `crates/executors/src/actions/review.rs` and `coding_agent_follow_up.rs` (Apache-2.0). Adapted the separation of review from bounded follow-up execution; no source copied.

## Work performed

- Added a closed Review result schema and a second host validation boundary.
  Error/blocker findings persist with append-only events and route through the
  published workflow definition. Specifications takes precedence for mixed
  findings; downstream stages rerun with validated summaries in their prompt.
- Enforced a fixed three-Review ceiling. Invalid provider output fails the Review
  attempt; repeated blocking output returns an explicit budget error which the
  guided launcher durably blocks for inspection.
- Added one atomic `run.completed_locally` event/projection. It rejects only the
  release handoff, cancels the waiting human attempt, clears task ownership and
  marks run/task done without calling a VCS host. Worktree/evidence remain.
- Added accessible dashboard confirmation and a run-page link to the two human
  completion choices. Updated product, architecture, flow, security, testing,
  beta, UI, walking-skeleton, decision, audit, task-index and plan documents.

## Artifacts

- Commits/patches: task 1020 implementation and documentation on this branch
- Migrations: none
- Logs/reports/screenshots: verification output and browser accessibility tree recorded in this worklog
- Configuration or policy hashes: not applicable

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| `rtk env -u CR_PAT mix test test/cuckoding/walking_skeleton_test.exs test/cuckoding/workflows/definition_test.exs test/cuckoding/workflows/gate_evaluator_test.exs test/cuckoding/state_machine_test.exs test/cuckoding/execution/scheduler_test.exs` | pass | seed 689246; 34 tests, 4 properties, zero failures |
| `rtk env -u CR_PAT mix test test/cuckoding/security test/cuckoding/execution/command_policy_test.exs test/cuckoding/execution/event_store_test.exs test/cuckoding/adapters/output_parser_test.exs` | pass | seed 256687; 10 tests, zero failures |
| `rtk env -u CR_PAT mix quality` | pass | final seed 761466; 264 tests, 10 properties, zero failures; warnings-as-errors compile, unused deps, strict Credo (203 files, 3267 mods/functions), Sobelow and Hex audit passed |
| `rtk env -u CR_PAT mix assets.build` | pass | Tailwind 4.2.1 and esbuild completed |
| `rtk git diff --check` | pass | no whitespace errors |
| `rtk curl -fsS http://127.0.0.1:4000/health` | pass | loopback health returned application/database/PubSub/web endpoint `ok` |
| Browser accessibility tree at `/` | pass with scope note | dashboard headings, navigation, operations, projects and Attention region rendered; current development data had zero pending approvals, so the new confirmation itself is covered by LiveView tests rather than a destructive browser click |

## Telemetry and operational evidence

No provider cost or token measurement was produced. Tests used deterministic
fake adapters and real temporary Git repositories. The full suite's two logged
fixture-worker crashes are intentional supervisor-restart tests, not failures.

## Decisions and deviations

- ADR-027 records the bounded Review-return and local-completion boundary.
- `rtk proxy` was used for exact source/instruction reads; repository commands otherwise use RTK filtering.
- The first full quality attempt passed all tests but strict Credo flagged three
  nested/complex helpers. The projection and route selection were split into
  smaller existing-domain operations; strict Credo and the final full gate pass.

## Risks and blockers

- Real-provider Review output, refresh and concurrent shared-profile use remain
  task 1018 acceptance gates. This task proves the parser/domain/UI path with
  deterministic structured results, not provider-native behavior.

## Handoff

Task complete. Next Phase 10 gate is task 1018 real-provider/shared-account
lifecycle acceptance, then controlled beta and the frozen signed release candidate.

## Checklist

- [x] Task acceptance criteria reviewed.
- [x] Relevant documentation updated.
- [x] Tests and checks recorded honestly.
- [x] Secrets and sensitive content excluded/redacted.
- [x] Residual risks and skipped work are explicit.
- [x] Task status and next owner are updated.
