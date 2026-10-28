# Recovery and restart

BOSS records intent before starting a CLI or changing Git, then records the result
after verification. A saved intent without a final receipt is an uncertain outcome,
not permission to repeat the command. Restart never signals a saved PID or launches
an unfinished stage automatically.

## What survives a restart

| Saved work | Restart behavior |
|---|---|
| Active manual run, check or review | Attempt becomes Interrupted with unknown process cleanup. Its task is not promoted. |
| Active managed workflow or integration | Delivery and unfinished stage become Interrupted; task history records the interruption. |
| Unstarted ordinary queue request | Becomes Paused; explicit Resume retains the original revision, check command, reviewer and UUID. |
| Running Autopilot | Becomes Paused, including unstarted members. Resume cannot rerun an interrupted member; its uncertain outcome stops the batch. |
| Approved Ready result | Remains approved for its saved commit. Publication still requires the existing integration gates. |
| Target already published, final receipt or postcheck missing | Published commit and retained checkout remain. BOSS neither resets the target nor calls the task Done. |

An unknown cleanup receipt blocks new execution across projects. Even if a process
appears absent now, its old PID is not durable ownership evidence. Waiting, pausing
or restarting again does not clear that uncertainty. There is no force-unblock or
automatic crash-resume control. Open the affected task to inspect the saved stages,
workspace and commit identities; retain them for diagnosis.

This differs from a known cancelled or failed workflow: after its processes are
confirmed stopped, a new explicit workflow can use the normal admission gates.
An unresolved integration intent remains protected against a fresh blind retry.

## Connected browser behavior

A coordinator restart can leave Phoenix and the browser connection alive. Recovery
therefore publishes each changed project's state after the top-level transaction
commits. Open run drawers show Interrupted, and queue/Autopilot controls show Paused
and Resume without reloading. Rollbacks, nested transactions and unchanged recovery
passes do not publish a successful update. Multiple changed rows in one project
produce one notification per recovery operation.

The UI remains a view of persisted state. Closing a browser does not own or cancel
the workers, and a missing notification cannot authorize execution.

## Acceptance evidence and limits

The existing native suites cover Repo loss during manual execution, checks, review,
managed implementation and integration, including a published target and merge
review. The current increment adds real-pool commit/rollback/no-op notification
checks and connected LiveView regressions. Exact commands/results are recorded in
[the worklog](../.worklog/2026-10-28.md).

`test/boss/backend_recovery_test.exs` kills a real child BEAM during implementation
and after publication while postchecks are running. A fresh application reacquires
the data-directory lock, retains the old receipts and exact target SHA, pauses the
batch and refuses new effects through both command replay and explicit Resume.
The tests verify cleanup of the finite CLI, its forked child and the native guardian
before their fallback deadline, preserving the user's dirty checkout. Removing
startup pause makes both tests fail their saved-state assertion.

These are two verified crash boundaries, not the complete recovery matrix. Linux,
real-provider acceptance, arbitrary detached sessions and safe release of
unknown-cleanup quarantine remain separate gates. No test fixture is a
live-provider guarantee.

Related contracts: [Autopilot](AUTOPILOT.md), [managed deliveries](MANAGED_DELIVERIES.md),
[queue](WORKFLOW_QUEUE.md), [manual runs](MANUAL_RUNS.md).
