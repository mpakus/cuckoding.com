# Autopilot

On a project page, choose **Autopilot** beside **Sync specs**, enter a trusted
check command and choose the independent reviewer. **Start Autopilot** authorizes
the entire current Backlog: present tasks in New, up to 256. The list must still
match when saved; larger or changed selections are refused, never truncated.
Failed tasks need an explicit new workflow from their details. Later imports and
source revisions are not silently added or adopted.

The saved batch pins each task's revision/version, check configuration, reviewer,
workflow UUID and integration UUID before effects. A retry of an uncertain Start
uses the same inputs and UUID. It returns the saved batch even if tasks or sources
have changed since admission.

One task proceeds through planning, implementation, checks, independent review
and automatic integration before the next task starts. Dependency readiness can
change the listed order; only Done satisfies a prerequisite. Known check failures
and review change requests use the existing three-cycle repair budget. Invalid
reports, changed candidates, unknown cleanup, failed integration, missing or cyclic
prerequisites, and exhausted repair budgets stop the batch with a reason.

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
