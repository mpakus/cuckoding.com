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

The native suites also cover Repo loss during manual execution, checks, review,
managed implementation and integration, including a published target and merge
review. Real-pool commit/rollback/no-op notification tests and connected LiveView
regressions cover coordinator-only recovery. Exact commands/results are recorded in
[the worklog](../.worklog/2026-10-28.md).

`test/boss/backend_recovery_test.exs` kills a real child BEAM at these checkpoints:

| Checkpoint | Required result after restart |
|---|---|
| Plan | The valid report and terminal CLI event cannot replace missing exit/EOF/cleanup. No implementation starts. |
| Implementation | Uncommitted candidate files remain; no check or approval is invented. |
| Check | The captured candidate commit/ref and earlier receipts remain; no review starts. |
| Review | The valid approved report and terminal CLI event remain incomplete execution, never a Ready approval. |
| Published target, postcheck running | The published SHA and retained checkout remain; no reset, repeated check or Done. |
| Completed Ready, paused before integration | Exact approval, checks, task events and saved request UUIDs survive. Only explicit Resume publishes the original candidate and runs the postcheck. |

For the five interrupted stages a fresh application reacquires the data-directory
lock, preserves earlier receipts and candidate identity, pauses the batch and
refuses new effects through command replay or Resume. The finite CLI, forked child
and native guardian must stop before the fixture's fallback deadline. Report
artifacts are confined to the test's exclusive scratch TMPDIR. A whole-VM crash may
leave a temporary report; restart never imports it as approval.

The Ready case completes ordinary review and cleanup before the crash. Recovery
preserves that finished evidence unchanged, including the reviewer/configuration
pins. Direct integration with the saved Autopilot UUID is refused while paused.
After Resume with an unchanged target, no model or earlier check repeats; only the
postcheck is new. Publication retains the exact approved SHA in a detached owned
checkout and leaves the user's dirty checkout untouched.

### Git changes while BOSS is stopped

Ready retains its historical approval; restarting does not rebind it to whatever
Git now contains. The restart fixture kills the backend, changes only its scratch
repository while no backend is running, then boots a fresh application. Saved
rows and call counts remain unchanged until explicit Resume.

| Offline change | Result after Resume |
|---|---|
| Candidate file changed, even with `assume-unchanged` hiding it from status | Block before new checks/review/publication. Preserve the changed file and the old evidence. |
| Candidate retention ref moved | Block before new checks/review/publication; preserve the moved ref and original candidate HEAD. |
| Target advances with a compatible independent change | Create a distinct two-parent merge candidate, run fresh checks and review, then publish that exact new SHA and run postchecks. Preserve the original approval. |
| Target history rewritten | Block before merge effects; retain the rewritten target without resetting it. |

The advanced-target case verifies ordered parents `[current target, original
candidate]`, distinct candidate path/ref/check ID, fresh check/review linkage,
both sets of file changes and the exact published SHA. All cases preserve the
user's separate dirty checkout. Model/check calls are finite local fixtures.

These checkpoints do not complete the recovery matrix. Narrower intent/effect/receipt
gaps, merge-stage crashes, further drift during resumed work, Linux, real-provider
acceptance, arbitrary detached sessions and safe release of unknown-cleanup
quarantine remain separate gates. No fixture is a live-provider guarantee.

Related contracts: [Autopilot](AUTOPILOT.md), [managed deliveries](MANAGED_DELIVERIES.md),
[queue](WORKFLOW_QUEUE.md), [manual runs](MANUAL_RUNS.md).
