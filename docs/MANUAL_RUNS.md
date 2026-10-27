# Manual Codex task attempts

On macOS, open a project task and select **Start Codex**. The local Codex CLI must
be installed and signed in on the PATH inherited by BOSS. The first adapter uses
`codex --ask-for-approval never exec --ignore-user-config --ephemeral --sandbox
workspace-write --json --color never -`; the saved task source goes through stdin.
The user-config flag does not promise disabling project rules, hooks or skills.
No approval/sandbox bypass is used. Provider access and quota are not inferred
from detection; a failed launch retains an explicit attempt result.

## Saved identity and workspaces

Admission uses one immediate SQLite transaction, a task-scoped UUID command ID,
the task's saved revision and state version. Replays return the original attempt,
including after completion or while another attempt runs. The global database
constraint permits one active attempt and blocks new work after unknown cleanup.
The current manual eligible task states are new, ready, failed, interrupted,
cancelled, blocked and needs_input. This action does not change task state.
New attempts also check [pinned dependency readiness](TASK_DEPENDENCIES.md) inside
the admission transaction; only Done satisfies prerequisites. Identical command
replay returns its saved attempt before this new-start gate.

Before creating Git state, BOSS stores a resolved base commit, fresh branch and
worktree path. It starts from the project's configured base branch commit;
uncommitted edits in the source checkout are not included or modified. Workspaces
live at `<data-dir>/projects/<project-id>/worktrees/<run-id>` on branches named
`codex/boss-run-<run-id>`. Existing matching workspaces are validated; mismatches,
symlink descendants, executable filters and conditional Git includes are refused.
Git hooks, fsmonitor, submodule recursion and remote protocols are disabled for
workspace preparation. BOSS does not reset, remove, merge or publish these runs.

Each attempt pins the task snapshot, independent of the revision currently viewed
in the drawer. Prompt plus source is limited to 1 MiB and rejected, never truncated,
when too large. A subsequent **Start Codex** creates a new attempt from the base,
not a resume of earlier edits. Every generated workspace is retained for inspection.
[Explicit source adoption](TASK_REVISIONS.md) changes only future task attempts.
Existing runs and their subsequent manual checks/reviews retain their original
source revision and candidate lineage.

## Process ownership and cancellation

The application owns the run; closing a browser/requester does not cancel it.
**Stop** routes to the actual live project-scoped worker through ETS, independently
of Manager/SQLite availability. The macOS C guardian owns a fresh process group,
releases the CLI only after the parent establishes/verifies that group, keeps
its leader unreaped until cleanup and supervises separate stdout/stderr.
A blocked consumer bounds upstream credit; cancellation and absolute deadlines
continue while callbacks are stalled. Control packets retry under pipe backpressure.

Cleanup proves the owned process group is empty, not arbitrary descendants that
escape with a new session/group. Detached daemons are unsupported. Worker death requests bounded group cleanup;
BEAM/Port-owner loss closes the guardian channel and triggers group termination.
Helper loss is unknown. Stored PIDs are diagnostic only and never signalled after restart.
A restarted manager marks unfinished attempts interrupted with unknown cleanup,
retains the workspace and blocks new runs. There is currently no recovery/unblock
UI; do not edit the database or delete workspaces to bypass this quarantine.

## Output and completion

Limits are 20 minutes, 8 MiB combined output, 256 KiB per JSONL line and 4,096
JSON events. The drawer retains at most 20 recent allowlisted event types, byte
counts and valid reported usage fields per attempt; arbitrary text, stderr,
commands and model/tool content are discarded. Progress is coalesced and a quiet
process can show its last persisted summary until later output or final receipt.
Missing usage stays unknown. The last ten attempts appear in one Repo-pinned
snapshot with task details. The immutable database history remains retained.

A finished receipt requires actual exit code zero, genuine EOF on both streams,
confirmed group cleanup and valid Codex turn completion. Cancellation takes
precedence over a later zero exit. Malformed/failed protocol, timeout, nonzero exit
or unresolved cleanup cannot produce success. **Codex finished — unverified**
means the CLI finished; task state, [explicit candidate checks](MANUAL_CHECKS.md),
[manual review](MANUAL_REVIEWS.md), integration
and Done remain separate. Any recorded workspace HEAD is diagnostic, not an approval receipt.

## Verification boundary

Application tests exercise native fixtures, real Git worktrees, fresh SQLite pools,
command replay, requester death, Stop and restart quarantine. Browser smoke uses
a finite local fake Codex only. No real model call was made for this increment.
A C compiler is required to build `priv/native/boss_guardian` on macOS. Linux and
Windows task execution, release packaging and detached-session containment remain
open. The separate macOS [managed workflow](MANAGED_DELIVERIES.md) now provides
plan, checks, review, bounded fixes and explicit integration before Done.
