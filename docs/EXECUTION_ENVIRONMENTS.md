# Execution and recovery

R040c's implemented Git setup uses a fixed native host helper, outside any agent
session: inspect metadata or initialize a missing standalone repository after
confirmation. R040d also previews explicitly selected bounded files and creates a
first local commit after separate confirmation, with a private candidate index and
exclusive index/HEAD/ref locks. Objects or staging may survive failed publication;
retain them for inspection. It reuses owned child groups and cancellation with a 15-second
native deadline, 20-second transport deadline and 25-second durable claim.
The root handle is pinned and checked against the registered device/inode;
unknown metadata and external layouts fail closed. This is not the future task
runner and grants no working-file access to agents. See [limits](SECURITY.md).

R050b also prepares a locked detached worktree from a consented committed HEAD,
using the same deadlines/process group and a private UUID-owned directory. It
excludes uncommitted source changes, refuses unsafe checkout mechanisms and keeps
partial effects without retry. This optional repository setup utility does not
implement task admission; future Start must authorize ordinary attempt creation
without adding per-task confirmation. Preparation allocates no runtime ports,
provider session or power assertion. Actual wake/reconciliation remains R060.

The first runner is a supervised host process runner using Git worktrees.
There are no containers, remote workers or claimed host sandbox boundaries.

## Owned execution

Each task attempt has a recorded worktree/branch/base, run directory, generated
runtime instructions, process group and optional leased loopback ports.
Parallel workers never share a writable checkout. Read-only roles receive
candidate/spec evidence through their own scoped sessions. Approved checks may
write build outputs to an owned verification area; source modifications invalidate
review. The original Arena checkout is not the working directory for agents.

Canonicalize paths and reject symlinks escaping granted roots. Keep generated
config private and separate from provider authorization profiles. Every launched
process records executable identity, PID, PGID, start identity, owner and result.
Pass argv without a shell; build child environments from a minimal allowlist.
Never import the user's shell startup environment or secret-bearing variables.

Validate named approved command declarations before execution. Model text cannot
become a shell command. Preserve full exit/timeout/cleanup outcomes and hashed
redacted logs. Instructions to an agent are not proof that its runtime enforces
the requested restriction; adapters report actual enforcement.

R040j stores user-approved check declarations only. Each Arena revision retains
literal argv, a relative working directory and finite timeout, with execution
disabled. Configuration reads no files and launches no process. The eventual
runner must bind this revision to Start authority, resolve/verify executables and
worktree paths, enforce grants and retain check receipts; those remain open.

## RTK and Ponytail

Contributors use RTK for every repository shell command and Ponytail full.
Managed role instructions carry the same defaults. App-owned repository shell
commands use the verified RTK wrapper after validating the underlying command.
Saved command declarations remain unwrapped so policy sees the actual operation.

Never filter JSON-RPC/ACP or other machine-readable protocol frames through RTK.
Use an exact-output bypass for those transports and for semantic incompatibilities,
recording the reason. RTK preserves exit codes, necessary failures and reviewed
command meaning. A missing required tool blocks the affected launch with a clear
setup action; no hidden installation or permission expansion. Pin/license-check
any bundled helper during packaging.

## Pause, stop, crash and sleep

Persist control intent before signalling a process. Pause closes admission,
saves a public checkpoint and quiesces workers using supported adapter behavior.
Stop cancels then uses an ownership-checked termination ladder. Check descendants
as well as the parent; only release leases/ports after verified cleanup.
Keep partial edits and evidence. Resume continues a compatible session or starts
a fresh one with public evidence; it never fabricates a restored process.

On startup/wake, reconcile commands, sessions, process identities, worktrees,
Git refs, ports and leases before scheduling. Distinguish a measured sleep gap
from a crash; expired heartbeat alone cannot justify a duplicate task.
Known-ended transient failures may retry within the battle's cumulative limits.
Uncertain launch/integration results require inspection before replay.

Use a macOS idle-sleep assertion only while eligible work is active. It cannot
guarantee lid-closed execution or prevent forced sleep. Persist sleep gaps, use
monotonic active durations and UTC deadlines; wall-time limits remain in force.
Quit checkpoints/stops owned work gracefully and keeps it resumable. Updates
must not race active mutations.

## Capacity and cleanup

Atomic task and resource claims enforce global, Arena, Tabula and provider
limits. CPU/memory observations are advisory on this runner. Required preview
ports use both durable leases and actual bind/listener checks; surface a race
or foreign owner rather than silently attaching to it.

Cleanup requires matching DB owner, canonical path, ownership marker, Git
identity, no live processes and a clean worktree. Dirty or uncertain work stays
available for inspection. No force deletion or reset. Archive/deletion needs a
preview and explicit human confirmation. See [flow](FLOW.md) for local integration
and [testing](TESTING.md) for crash/sleep/parallel acceptance.

R040e brief planning uses R020d's private-profile/empty-scratch execution boundary.
It supplies only a consented typed brief and frozen Speculator instructions, with
no project filesystem grant or worktree. It is a bounded structured turn, not the
repository task runner described above. No successful real-account planning turn
has yet been recorded; protocol fixtures do not establish provider enforcement.
