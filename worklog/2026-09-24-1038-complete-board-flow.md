# 1038 — Complete board flow

Claimed on feature/1038-complete-board-flow from clean local main at 5fa55bc.
Task 1037 was committed and fast-forward merged with `rtk git commit -m
'feat(agents): discover installed runtimes and document workflow contract'`,
`rtk git switch main`, and `rtk git merge --ff-only
feature/1037-agent-path-discovery`. No remote push or native rebuild yet.

The preceding goal turn made progress: documentation and requirements changed,
the implementation gaps were established, and current source now passes 10
properties/314 tests and all native checks. No blockers declared. This task
retains all requirements in the active goal, with acceptance in its task file.

Applied Ponytail full 4.10.0 (MIT), workflow-and-kanban, elixir-phoenix-liveview,
local-runner, security-review and quality-gates. Read required product,
architecture, database, flow, security, execution and reference documents.
`rtk proxy` exceptions are exact source reads and bounded script assertions
where filtering would change semantics. No raw process args/environments or
credential files may be displayed. Current XERJ listener check
`rtk lsof -nP -iTCP:9200 -sTCP:LISTEN` found no listener; no completed-index claim.

## Initial audit

Existing reusable accounts/model copies, board intake/import, scheduler and
durable project admission should be reused. Gaps: proposed-task second-model
review, accepted role names/return loop, custom role execution/permissions,
explicit local-completion policy, and effective task/global pause/stop controls.
The installed bundle and live process state have not yet been revalidated.

## Delivery handoff and default roles

The audit found a root-cause handoff bug: all three stage prompts included only
the card title, and the persisted specification was never passed to subsequent
roles. Every stage now receives the task description; Implementor and Reviewer
receive the latest validated specification text, while a returning Speculator
receives the previous spec and full validated finding summaries/evidence.
Specification files remain durable per-attempt artifacts. Read-only roles now
explicitly deny writes in their requested grants.

New role defaults use Speculator/Implementor/Reviewer. Both correction labels
in the new workflow route to Speculator, retaining the finite review budget.
The executor now reads the run's snapshotted definition instead of today's
default when routing findings. New boards publish a new default version when
the definition changes; old boards and run snapshots are not mutated. Run
setup displays the snapshotted role name, including custom names.

Reference inspection: XERJ was unavailable, so inspected Agetor at pinned
eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a (MIT, LICENSE inspected),
src/bun/workflow-hold.test.ts:50-65. It reinforces keeping a task running across
its full workflow, distinct from individual agent stages. Cuckoding keeps its
own SQLite transitions/attempts and does not copy the peer's driver or state
model. The actual handoff fix reuses local run/stage/artifact/request code.

`rtk mix test test/cuckoding/project_onboarding_test.exs
test/cuckoding/workflows/definition_test.exs test/cuckoding/walking_skeleton_test.exs
test/cuckoding/project_workflow_test.exs` passed 2 properties and 52 tests before
the final role-label UI adjustment. Coverage includes the real structured-spec
parser, description/spec delivery to separate adapters, spec revision after a
code finding, preserved artifacts, full return loops and immutable older workflow
versions. This remains deterministic provider-fixture evidence, not live-provider
acceptance or completion of the full goal.

After the role-label UI change, `rtk env -u CR_PAT mix quality` passed 10
properties and 316 tests, formatting, warnings-as-errors compilation, strict
Credo, Sobelow and dependency audit. Documentation now distinguishes new
defaults from legacy immutable snapshots and retains the unimplemented goal
items. This verified slice is integrated into local main before continuing the
proposal-review work; task 1038 remains in progress.

## Proposal review before task import

The delivery-handoff slice was fast-forward merged to local main at `00ce3db`.
The next slice reuses planning runs and stage attempts for a distinct configured
model/runtime to review unimported proposals. It validates a closed bounded
response, unchanged proposal IDs and confined source files; updates descriptions
and specs; retains comments and before/after revisions in an append-only event;
and saves a private Markdown report with its hash. The run page offers the
eligible roles, shows report/comments, and disables import during review.
Imported batches cannot be rewritten by model review. Invalid responses leave
originals unchanged and allow retry.

Retry coverage found a shared failure-command key reused across attempts,
which could leave the next failure marked Running. The key now identifies the
attempt, retaining command idempotency without conflating separate failures.

- `rtk env -u CR_PAT mix test test/cuckoding/board_task_intake_test.exs`:
  8 tests, 0 failures (same-model rejection, review revisions/report/grants,
  successive failures/retry, import exclusion and rendered report/model picker).
- Initial `rtk env -u CR_PAT mix quality`: formatter rejected a conditional
  interpolation layout; simplified the expression and formatted it.
- Next quality run: 10 properties, 319 tests, 0 failures; strict Credo rejected
  one deeply nested update callback. Extracted that update into a small helper.
- RTK proxy exceptions continue to be exact source reads and patch-support
  inspections. No process argv, environments or raw provider logs were read.
- This is source and deterministic fixture evidence, not a native build or
  real-provider acceptance claim. All full-flow acceptance gates remain open.

Final proposal-review verification: `rtk env -u CR_PAT mix quality` passed
formatter, compilation with warnings as errors, 10 properties and 319 tests,
strict Credo, Sobelow and dependency audit. Cleanup reruns initially found two
remaining nested expressions and an invalid zero-argument capture; the final
transaction callback is a normal function and all checks above passed.

## Explicit automatic local completion

Proposal review was fast-forward merged to local main at `ca198ec`.
The next slice adds an explicit manual/local completion choice at project or
single-run start. It records `run.completion_policy` atomically with start,
then reuses the validated, transactional local-completion path after Review.
Automatic completion rejects the unused release approval, preserves the branch,
worktree and evidence, and never invokes a VCS host. Existing runs without an
event remain manual; later project changes cannot alter a started run's choice.

Migration `20260924120000` only adds a constrained `completion_mode` column to
project controls, defaulting prior records to manual. The migration regression
upgrades a copy of the prior schema, checks unchanged fields, the new default,
the invalid-value constraint, foreign keys and SQLite integrity. No application
database or user data was migrated during these source checks.

- Focused first run: 51 tests, one assertion mismatch because event payloads
  correctly include correlation metadata. Changed the assertion to match the
  policy fields. Consolidated migration-copy checks into the existing migration
  test to avoid duplicate module compilation warnings from separate fixtures.
- `rtk env -u CR_PAT mix test test/cuckoding/walking_skeleton_test.exs test/cuckoding/project_workflow_test.exs test/cuckoding_web/project_edit_live_test.exs test/cuckoding/shared_authorization_migration_test.exs`:
  50 tests, 0 failures, including explicit single-run and project admission
  completion, immutable decisions, no remote branch/release stage, UI selection,
  and prior-schema copies.
- `rtk env -u CR_PAT mix quality`: formatter/compiler, 10 properties and
  322 tests, strict Credo, Sobelow and dependency audit passed.
- `rtk git diff --check`: passed. Documentation now distinguishes the explicit
  local choice from remote approval, including the root contributor contract.
- App rebuild, browser acceptance, additional roles/permissions and effective
  per-task/global controls are still open; this does not complete task 1038.
