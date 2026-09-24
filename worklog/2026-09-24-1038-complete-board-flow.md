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

## Process control foundation

Automatic local completion was fast-forward merged at `8da14c3`.
Runner inspection found that `pause` only verified ownership and that `stop`
replaced the workflow's waiting caller. Pause now suspends verified owned groups
with STOP, resume uses CONT and the original remaining timer, stale timer
messages cannot kill a resumed process, and stop replies to every waiter.
Signals, pause/resume observations and measured pause duration are durable
events; stage active time excludes measured pauses while wall time retains them.
Unregistered process workers cannot be claimed as safely resumed. Worktrees and
artifacts are retained; process cleanup still verifies recorded ownership.

`Lifecycle.pause` now obtains and persists a valid checkpoint before signaling.
Its recovery drill checks that the pause checkpoint precedes STOP and the
hibernate checkpoint precedes termination. A failed checkpoint leaves the
preview responsive, and a paused process can still be stopped without leaving
descendants or stranding its workflow caller.

- `rtk env -u CR_PAT mix test test/cuckoding/execution/local_process_runner_test.exs test/cuckoding/execution/lifecycle_test.exs test/cuckoding/execution/preview_test.exs test/cuckoding/power/manager_test.exs`:
  23 tests, 0 failures after adapting the drill's checkpoint ordering assertion
  to distinguish pause signals from termination signals.
- `rtk mix credo --strict`: passed.
- One formatting-only gate required a second formatter pass on a multiline test
  call; `rtk mix format --check-formatted` then passed.
- End-to-end task/global controls still require orchestration admission,
  cancellation/pause coordination and UI wiring. Runner capability alone does
  not satisfy those acceptance items.

Final runner verification: `rtk env -u CR_PAT mix quality` passed formatter,
warnings-as-errors compilation, 10 properties and 324 tests, strict Credo,
Sobelow and dependency audit. `rtk git diff --check` passed.

## Run and workspace controls

The runner foundation was fast-forward merged at `35fde75`. RunControl now
records admission and user actions durably, coordinates stage launches with
pause/resume/stop, preserves attempt checkpoints and stops owned groups while
retaining worktrees and evidence. Workspace pause closes admission before its
target snapshot; resume only resumes runs paused by that workspace action.
Individually paused runs remain paused. Stop can retry cleanup for terminal
runs with recorded live processes; port leases expire normally. A stopped task
can prepare a fresh run without rewriting the previous attempt. Intentional
cancellation no longer produces a false provider-failure event.

Run and dashboard controls expose these operations, including confirmation for
stop and visible partial-failure feedback. A missing live orchestration worker
cannot be claimed resumable after a restart. Unconfirmed process control is
explicitly reported; durable paused/cancelled state alone is not signal evidence.

- Initial focused checks exposed a shared transition helper indexing keyword
  options with a string when wait_reason was nil. Fixed that shared helper.
  Nested callback and alias-order Credo findings were simplified and corrected.
- `rtk env -u CR_PAT mix test test/cuckoding/run_control_test.exs test/cuckoding/board_task_intake_test.exs test/cuckoding/project_workflow_test.exs test/cuckoding/walking_skeleton_test.exs`:
  57 tests, 0 failures. Fixtures launch real owned shell processes and assert
  halted output, retained attempt identity, measured pause time, stop replies,
  fresh retries, global admission and LiveView controls.
- `rtk env -u CR_PAT mix quality`: formatter, warnings-as-errors compilation,
  10 properties and 329 tests, strict Credo, Sobelow and dependency audit passed.
  Expected intentional plugin-crash fixture messages occurred, not test failures.
- A bounded `rtk proxy python3` inspection filtered `lsof -c sh -a -d cwd -Fpn`
  to temporary run-controls fixture directories and returned no remaining
  processes. No argv, environment or raw provider logs were read. This exact
  metadata filter and source reads are the continuing RTK proxy exceptions.
- Native/browser/provider acceptance and executable custom roles/permissions
  remain open. These source checks do not finish the full task or active goal.

## Executable custom roles and permissions

Run/workspace controls were fast-forward merged to local main at `00b3957`.
Custom roles now select planning-only, after Speculator, or after Implementor,
with read-only or worktree-write delivery grants. Existing custom metadata
defaults to planning-only/read-only. Saved role configuration is confirmed and
audited; new/explicitly updated boards get a versioned stage sequence, while
prepared and historical runs retain their snapshots. Delivery launch resolves
every scheduled role; planning-only assignments do not block delivery setup.
Built-in Speculator/Reviewer remain read-only, and approval/release keys are
reserved. Neither role instructions nor reports can alter runtime grants.

Additional roles pass reports downstream and to Reviewer, retain hashed report
artifacts, and repeat within the correction loop. The host commits permitted
changes; unexpected writes from a read-only support role block the workflow
and remain uncommitted for inspection. The form does not expose arbitrary
graphs, external paths or network access; existing adapter enforcement limits
remain explicit. No new dependencies, migrations or provider integrations.

Source tracing reused the existing Definition, ProjectOnboarding, role snapshot,
AgentRuntime, WalkingSkeleton, GitService and GateEvaluator boundaries. No peer
source was copied; the preceding unavailable-XERJ/source-inspection limitation
still applies. Ponytail full and security/quality gates remain active.

Verification/fixes:

- Initial focused run: 60 tests and 2 properties, one fixture mismatch after
  instructions were made snapshot-owned. Updated the fixture to persist its
  declared role instructions in the immutable run snapshot.
- Additional checks caught a fixture saved-provider mismatch and exposed a
  real GitService return bug: a clean commit attempt returned an inspection map
  as a successful environment. All callers were inspected; the shared commit
  service now returns `candidate_revision_unchanged`, with a focused assertion.
  Read-only custom stages no longer attempt an unnecessary candidate commit.
- `rtk env -u CR_PAT mix test test/cuckoding/walking_skeleton_test.exs test/cuckoding/project_workflow_test.exs test/cuckoding/execution/git_service_test.exs`:
  53 tests passed before the final read-only-write adversarial check was added.
- A strict Credo complexity finding was resolved by extracting report text
  assembly from the already existing objective function.
- Final `rtk env -u CR_PAT mix quality`: formatter, warnings-as-errors compiler,
  10 properties and 332 tests, strict Credo, Sobelow and dependency audit passed.
- `rtk git diff --check`: passed. Exact source reads continue to use `rtk proxy`.
- A bounded `rtk proxy python3` Markdown-link assertion checked all seven changed
  contributor/product documents; all local link targets exist.
- Native/browser/provider acceptance, dynamic board visibility and the current
  one-app launch are still outstanding. Task 1038 and the full goal remain active.

## Live board progress

Custom roles were fast-forward merged to local main at `190c84c`. The next
slice reuses AgentFloor's durable latest-attempt/session projection for each
active board task, exposing current stage, saved role name, runtime, observed
or explicitly requested model, and elapsed wall time including pauses. Dashboard
and agent inspectors now use the same snapshotted role names. No new state store,
runtime or query per card; existing projection queries are reused in batches.

Applied the animate skill for spatial consistency on occasional automatic
state moves: native WAAPI, transform only, 200 ms, prescribed strong ease-in-out.
Keyboard-focused cards, reduced motion and background tabs stay instant. Other
updates do not animate, interrupted animations cancel before retargeting, and
preference changes cancel immediately. No dependency or perpetual indicator.

- `rtk env -u CR_PAT mix test test/cuckoding_web/board_live_test.exs test/cuckoding_web/status_live_test.exs test/cuckoding_web/agent_floor_live_test.exs`:
  25 tests, 0 failures, including parallel-card state/model/role rendering and
  independent pause updates. A missing alias warning on the first 24-test run
  was fixed before this rerun.
- `rtk node test/task_board_motion_test.cjs`: native hook regression passed.
- Full quality and rendered/current-bundle checks follow; task remains active.

Board verification follow-up: `rtk env -u CR_PAT mix quality` passed formatter,
warnings-as-errors compilation, 10 properties and 333 tests, then stopped on one
test alias-order finding. Reordered the aliases; `rtk mix credo --strict`,
`rtk env MIX_ENV=test mix sobelow --config`, `rtk env -u CR_PAT mix hex.audit`,
`rtk mix format --check-formatted`, `rtk node test/task_board_motion_test.cjs`
and `rtk git diff --check` then passed. This was a metadata-only test fix, so
the already passing full test suite was not repeated. Current process inspection
used only executable, PID, parent PID and start identity; no argv/environment.
