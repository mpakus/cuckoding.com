# Autopilot

## Start from project documentation

Add a repository with **Plan tasks from documentation** selected. BOSS suggests
this mode for a repository with a `docs/` folder. Choose another committed
documentation directory with the folder picker if needed. Leaving the target
blank creates a local BOSS publication branch at the current commit. The project
page opens the Autopilot panel with that target. Select a trusted check command
and press **Start Autopilot**. BOSS suggests `mix test` for Mix repositories.

A read-only Codex planner compares committed Markdown with the code at the saved
Git base and returns up to 32 outstanding tasks. New Starts pin planning version 1:
a rejected plan can pass to another saved model, with at most three attempts under
one 20-minute deadline. Each attempt is saved before execution, with its exact
model and source commit; terminal receipts retain fixed validation codes and
response size, never raw model output. The panel shows this attempt history. BOSS validates the source paths
and dependency graph, then saves the generated task specifications and batch
in one transaction. The same Start dispatches the first eligible task. An empty
plan records that the planner found no outstanding work. Original Markdown stays
on disk and generated specifications are stored with their source paths and SHA.

The whole response is limited to 32 KiB of UTF-8 JSON, with at most 4,000 bytes per
task specification. The prompt and schema describe the task, field and list limits.
Recovery receives the original documents, trusted checks and a fixed diagnosis; it
cannot truncate a rejected response into acceptance. Only the latest successful
attempt's validated plan hash can authorize task and batch creation.

Stop, uncertain cleanup, source/target drift, authentication, quota and provider
protocol errors halt planning. Two distinct models failing during generic startup
also stop further calls. Historical planning version 0 keeps its single attempt;
failed historical requests remain immutable. Replaying a Start returns its saved
request and does not launch another model. A fresh Start is a new request.

Planning runs once per documentation project. Later Starts use remaining eligible
unfinished cards. Existing task-spec projects keep their Markdown watcher and
ordinary Start unless explicitly converted. A changed target, invalid plan or stopped planner prevents the
handoff. After a coordinator restart, interrupted planning retains unknown cleanup
and requires inspection. Planning has a Stop control.

### Correct a project imported in the wrong mode

If a documentation bundle was registered as task specifications, instruction files
such as `SKILL.md` or `AGENTS.md` may have become cards. Use **Plan from documentation**
on the idle project to preserve those cards as reference history and enable the
documentation planner. This action does not call a model or start work. Root,
documentation directory and publication target stay unchanged.

Conversion saves an immutable receipt and the exact imported task/revision/version
membership in one transaction. Old task states, events, source revisions and run
receipts remain unchanged and readable. Reference cards leave the execution board
and cannot receive new workflow, manual, check, review, source-adoption or integration
commands; an identical historical command UUID still replays its saved receipt.
Active work, unknown cleanup or retained publication intent prevents conversion.

Then use **Start Autopilot** with a trusted check command. This separate Start pins
the committed Git source, derives executable tasks and dispatches the first one.
Generated IDs, dependencies and synthetic paths are namespaced by the intake UUID
so a planner's `bootstrap` cannot overwrite an old imported `bootstrap` task.
Invalid planning leaves the reference history intact and creates no partial tasks
or batch. The existing check, independent review and exact-commit publication gates
still determine Done.

## Start from existing task specifications

On a project page, choose **Autopilot** beside **Sync specs**, enter a trusted
check command and choose the independent reviewer. The menu lists the agents
assigned to Reviewer. Codex, Claude, and Cursor can run that review. When the
Reviewer role has no agents yet, Codex and Claude remain available. Planning
and implementation use the Implementer role. Questions and stuck diagnosis use
the Analytic role. **Start Autopilot**
authorizes
a fresh snapshot of all eligible present unfinished tasks: New, Failed, Blocked
and Needs Input, up to 256. Previously failed tasks receive new workflow UUIDs;
old receipts remain immutable and Done tasks are excluded. Tasks with active work,
unknown cleanup or unfinished integration are ineligible. The list must still
match when saved; larger or changed selections are refused, never truncated.
Historical routing-version-1 batches retain their original New-only snapshot.
Later imports and source revisions are not silently added or adopted.

The saved batch pins each task's revision/version, check configuration, reviewer,
workflow UUID and integration UUID before effects. A retry of an uncertain Start
uses the same inputs and UUID. It returns the saved batch even if tasks or sources
have changed since admission.

Autopilot runs one task at a time through planning, implementation, checks,
independent review and integration. Only Done satisfies a prerequisite. New starts
pin the [autonomy policy](AUTONOMY.md): questions and recoverable failures receive
another model's diagnosis, followed by fresh implementation, checks and review.
The policy permits five implementation cycles; historical batches retain their
saved cycle budget and model behavior.
A Failed, Needs attention or Needs input task with verified cleanup and no
integration intent keeps its saved reason while independent tasks continue.
A shared model/CLI failure stops the batch before another task is admitted;
unstarted tasks retain their states. This includes typed catalog/provider failures
and exhausted legacy strong-model routes. Repeated clean startup failures across
two distinct strong models before any successful plan are also shared evidence;
invalid reports and rejected code are not classified as provider failures.
When no runnable tasks remain, the batch reports outstanding work. Cancellation,
unknown cleanup, target drift and failed integration can still stop the batch.

The existing [delivery gates](MANAGED_DELIVERIES.md) remain mandatory. Ready is
not Done: publication and postchecks must succeed for the exact reviewed commit.
An advanced target requires a new merge candidate, checks and independent review.
No scheduler action can declare a task Done directly. Completed tasks stay Done;
there is no automatic branch reset or endless fresh retry after a terminal failure.

The target branch must be free of user checkouts. An early read-only preflight
refuses a checked-out or unavailable target before any model call. Publication
checks that condition again. BOSS does not switch your checkout automatically.

## Watch and control

The Autopilot panel shows each saved task's current state and links to its details
with plan, reviewer findings and saved stages. The board refreshes as tasks move.
Active and paused batches reopen their controls after a browser reload. Closing
the browser does not stop the workers.

If the Start reply cannot be confirmed, BOSS keeps the original request and its
inputs. A current read of that exact saved batch confirms admission and restores
the controls for its saved status without launching another workflow. Unrelated or stale reads keep the
request uncertain; retry uses its saved inputs and UUID.

- **Pause Autopilot** lets the admitted workflow finish through review approval;
  it prevents the next task or integration from starting. An integration already
  admitted may finish. Pause does not suspend a CLI in the middle of its work.
- **Resume Autopilot** continues the saved authorization, with version checks.
- **Stop Autopilot** signals its live worker directly and cancels remaining
  requests. Retained files, prior results and already published commits remain.
  A stale Stop still withdraws this batch; it cannot stop a different batch.
- After a server restart, unstarted work pauses and needs explicit Resume.
  Interrupted workers are quarantined, never respawned from saved PIDs or status.
  Connected pages receive the persisted pause even when only the coordinator restarts.

Running Autopilot reserves global dispatch for its sequential work. The ordinary
workflow capacity setting stays unchanged. Existing manual Start/Queue requests
do not gain automatic integration. Paused requests still reserve their tasks;
unknown process cleanup remains a global admission barrier.
Waiting or restarting does not clear it; see [recovery behavior](RECOVERY.md).

Checks use the installed tools from the PATH that launched BOSS; the bundled
runtime runs BOSS itself. The project still needs its own compatible toolchain.
A corrected runner does not retry an old blocked batch: inspect its task details
and explicitly start a fresh workflow. Previous failed receipts stay unchanged.

Codex plans, implements and fixes; the selected Codex or Claude reviewer receives
the saved evidence. These calls use configured local accounts and may incur
charges. Development acceptance uses finite fake CLIs; it does not establish
real-provider quality or Linux support. No raw CLI transcript or check output is
retained; fixed diagnostics and sanitized receipts explain failures.

## Recover a checked-out target

When the panel reports “The integration target branch is checked out”, inspect
`git worktree list --porcelain` in the registered repository. Find every checkout
whose branch matches the project's saved integration target, often `main`.
For a clean checkout, explicitly switch it to a new observer branch at the same
commit; for example, with a new unused branch name:

```sh
rtk proxy git -C /path/to/checkout status --short
rtk proxy git -c core.hooksPath=/dev/null -C /path/to/checkout switch --no-track -c codex/boss-observe
rtk proxy git -C /path/to/checkout worktree list --porcelain
```

Inspect dirty work before changing it; do not force/reset/stash it as part of
this repair. Verify unchanged HEAD, target ref and working files, and no checkout
still attached to the target. Keep the observer branch checked out while Autopilot
runs: its files stay at the original commit while BOSS advances the target in its
own integration worktree. Switching back to the target restores the blocker.

This early refusal blocks the batch and cancels its unstarted requests. After
repair, use a **new Start Autopilot** with the current Backlog and trusted checks;
Resume or replaying the old Start UUID does not create a fresh workflow. Historical
blocked/cancelled entries remain truthful. The repair itself starts no model calls.


## Verify a retried task before continuing the Backlog

For an explicitly requested retry of a stopped task, open its details and choose
**Start workflow** with the selected reviewer and trusted check command. Preserve
the stopped delivery and its evidence. Follow the new plan/check/review stages;
**Ready** still requires **Integrate approved result** for this manual workflow.
Verify exact publication, postchecks and **Done**, then start a new Autopilot for
the current Backlog. The task just completed is excluded from that snapshot.
A terminal refusal stops this sequence; it does not authorize another fresh retry.

For a lost or expired browser token, an existing local IEx console can issue
`Boss.LocalAccess.new_token()`; enter its result directly in the unlock form.
The token is one-use and expires after ten minutes. If no console is available,
restart only an explicitly authorized idle instance with a consistent private
database backup and its original data directory. `bin/boss start_iex` keeps a
local console attached without enabling distribution/RPC. Never capture its
Terminal I/O, put tokens in URLs, or weaken browser authentication.

The 2026-10-31 owner-authorized Task1 run reached a passing check on candidate
`03e93ae0c0715d0d875b17d9a0057fd351376e0a`, then stopped Blocked at the
three-cycle limit. Review returned `changes_requested`: independent egress
enforcement, Oban resend prevention, production-adapter security regressions and
broader IP property tests remained incomplete (10/14 criteria passed). Earlier
check failures were missing Req in fresh check worktrees; the final test setup
excludes Req from the test environment, so passing fake-transport tests do not
establish production-adapter coverage. No result was integrated and the remaining
45 New tasks were not admitted to Autopilot. This is failure-path evidence,
not full Task1-to-Done or full-Backlog acceptance.

A fresh project registration defaults its base branch to the current checkout.
Choose the intended integration target explicitly when registering from an
observer branch. Keep the registered target free across all worktrees before
starting Autopilot. A direct workflow that is already active holds admission
until its execution settles.
