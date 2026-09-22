# 1028 — Autonomous project-flow audit

Claimed 2026-09-22 on clean `main` at `4546f85`.

Acceptance: compare every requested journey step with source, distinguish
implemented behavior from intent, and create a next-goal document without
changing execution or weakening human/security gates.

Inspected `docs/PRODUCT.md`, `ARCHITECTURE.md`, `DB.md`, `FLOW.md`, `SECURITY.md`,
`EXECUTION_ENVIRONMENTS.md`, `DOCUMENTATION_AUDIT.md`, `AGENT_AUTHORIZATION_FLOW.md`,
the Phase 5 scheduler task, and current Agents/project/board/task/run LiveViews,
`ProjectWorkflow`, `BoardTaskIntake`, `GuidedRun`, `WalkingSkeleton`, and
`Execution.Scheduler`. The upstream Ponytail 4.10.0 skill is MIT-licensed;
full mode kept this a documentation-only change.

Result: `docs/AUTONOMOUS_PROJECT_FLOW.md` records the current/target matrix,
durable project-level Start, concurrency and blocker semantics, and ordered
implementation/verification slices. No migration, provider process, or
credential operation was performed. Current scheduler tests prove admission
planning, not automatic production dispatch.

Verification: `rtk proxy test -f docs/FLOW.md`,
`rtk proxy test -f docs/AGENT_AUTHORIZATION_FLOW.md`,
`rtk proxy test -f docs/SECURITY.md`, and
`rtk proxy test -f docs/AUTONOMOUS_PROJECT_FLOW.md` passed.
`rtk git diff --check` passed before staging; the staged diff was checked
again before commit. No product tests were run because behavior did not change.

Open decisions: local-only auto-completion versus the current human gate,
critical-blocker count/default, reviewed task import, and same-agent parallel
capacity. Real-provider shared-login acceptance remains task 1018; signed-app
release gates remain open. The next owner should choose those product semantics
before implementing autonomous dispatch. Do not label this audit as shipped
autonomy.
