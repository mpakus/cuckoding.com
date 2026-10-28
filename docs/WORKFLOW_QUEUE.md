# Workflow queue

BOSS scheduling uses finite native CLI fixtures on macOS for verification.
Commands and browser/full-suite evidence are recorded in `.worklog/`.

The task drawer offers **Start workflow** for immediate admission and **Queue
workflow** for an explicit saved request that can wait for a free worker or
unfinished dependencies. Both use the entered check command and selected reviewer.
**Workflow capacity** sets the global limit to **1–3**, default **2**, across all
projects. The saved setting survives restart. A stale settings form must reload;
lowering the limit below currently owned workers is refused until they exit.
Changing the limit never cancels a workflow. Manual runs/checks/reviews and
integration remain exclusive. Only **Done** satisfies a dependency; Ready does not.

Queueing does not change the task's workflow state. The queue entry displays its
saved source revision, reviewer and check command. **Cancel queue** withdraws an
unstarted request. Once it starts, use the delivery's **Stop** action. Cancelling a
queue entry cannot claim to stop an already launched worker.

## Saved authorization

The request stores its command UUID, project/task, pinned source revision and task
version, normalized check argv/config hash and reviewer before effects. Retrying
the same UUID returns the saved request; different input conflicts. An uncertain
browser request keeps both its input and its original Start/Queue action fixed.
Selecting another historical source does not change the task or queued request.

One queued or paused request is allowed per task, with at most 32 globally. A
pending request blocks a new manual or immediate managed start and source adoption
for that task. Cancel it before choosing a different source or execution. Saved
requests and terminal history cannot be rewritten or deleted. The drawer reads
the latest three requests for its selected task in a project-scoped transaction.

Dispatch reads persisted intent. Within one Repo-pinned immediate transaction it
checks the task revision/version/state, dependency graph and global execution
capacity, then creates the delivery and links it to the request. Only committed
new admission can launch a worker. Duplicate ticks or request replays cannot launch
another copy. Waiting entries do not churn task state or write timestamps.

An externally changed task makes its old request **Stale**, without launch. The
queue never substitutes newer source or a different check/reviewer. Invalid or
cyclic dependencies do not dispatch; missing or unfinished prerequisites continue
to block. A bounded rotating scan allows an independent request behind blocked
entries to proceed.

## Restart and cancellation

On Manager startup, unstarted queued requests become **Paused**. They require
explicit **Resume** with their existing saved inputs. A cancelled or stale request
cannot be resurrected by Resume or a late tick. A started request remains linked
to the same delivery; it is not returned to the queue after failure or restart.

Loss of a worker, Repo or receipt follows the existing interruption/quarantine
rules. Unknown cleanup blocks new execution even when another worker was running.
No old PID is reused and no model stage is respawned. Repo loss terminates all
owned workers; a normal Stop addresses only its selected worker through the
project-scoped live registry, independently of Manager/Repo mailbox availability.

## Parallel work and integration

Each workflow has its own saved base commit, unique worktree, branch and private
snapshot index. The read-only planner returns `file_scopes`: either `null` for an
unknown prediction or 1–64 objects with `path` and `kind` (`file` or `directory`).
Paths are literal repository-relative UTF-8 names, at most 1024 bytes each; no
empty/dot/parent segments, `.git` (including case aliases), glob characters,
backslashes, colons, ASCII control characters or trailing slash. Older saved plans that
omit this field remain unknown. Predictions appear in the workflow history.

Immediately before the first implement step, an atomic check compares its saved
plan with acquired scopes in the same saved Git common directory. Equal paths or
whole-segment ancestors overlap, including ASCII case aliases and file/directory
replacement. Non-ASCII known paths conservatively overlap every known peer scope,
avoiding differences between SQLite and filesystem Unicode comparison. Planning
alone holds no claim, so simultaneous plans cannot deadlock each other.

An overlapping workflow waits before writing while retaining its worker slot.
The owner holds the scope through fixes, checks and review until it becomes Ready
or terminal. Waiting does not rerun planning, create steps or update timestamps;
Stop remains available. Scope checks and SQL guards share one comparison policy.

Unknown scopes do not block peers and show a potential-conflict warning. Even a
known prediction may miss edits: it is neither a filesystem restriction nor proof
of semantic compatibility. Worktree separation and scope predictions never replace
the integration checks below.

Integration remains an explicit globally exclusive operation. After one parallel
candidate is integrated, another candidate based on the old target gets a fresh
merge candidate, saved checks and selected review before publication. Its original
approval remains historical. Conflicts, check/review failure or another target
change stop the attempt; no automatic repair or retry occurs. The unchanged-target
fast-forward path remains available. See [Managed delivery](MANAGED_DELIVERIES.md).
Automatic rebase and merge-conflict repair remain separate work.

Tests use finite fake CLIs, real Git and isolated SQLite pools. They are not
real-provider authentication or paid model acceptance. Linux execution and broader
recovery/release gates remain open.
