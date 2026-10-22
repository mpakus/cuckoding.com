# Execution and recovery

## Bounded execution and task waves

R060b permits explicit bounded retry of settled transient provider failures only
under the frozen `provider-retry-v1` contract. Read-only stages keep their native
integrity checks; a failed Implementor starts in a new owned worktree through
coordinator/Speculator. Failed effects stay retained. Native operations and
interrupted/uncertain sessions are never retried by this control.

R060j adds SQLite-owned 5/20-second automatic waits for known settled connection,
busy-profile, timeout and launch failures under a separate frozen Start policy.
It reuses R060b limits and fresh attempts/worktrees, releases the worker during
the wait and checks exact bindings/deadlines before dispatch. Cancel automatic
retry retains manual inspection/Retry; restart cancels pending waits. Generic
provider/turn failures stay manual and uncertain native work never retries.

R070d permits two independent task pipelines per wave within the two global
supervised stage workers. SQLite owns each task stage/claim; exact saved
connections permit one provider turn. Native repository I/O waits in a bounded
cancellable local process queue, with native ownership/locks still authoritative.
Checks, independent review and integration run serially after implementation;
combined candidates receive new review/check evidence. Old Starts remain
sequential per board. R070e adds explicitly paired role bindings; real-provider
parallel acceptance remains open. Each task starts from the last independently reviewed battle head; failed review creates a new worktree and returns through Speculator. Checks use a separate exact-candidate clone. The initial `codex-check-single-process-v1` grant supports native commands in `/usr/bin` or `/bin` only, with no subprocess spawning; scripts and Mix/npm toolchains are refused. The Implementor connection must have verified Codex `0.162.0-alpha.17.2`. Configured command checks and independent review gate completion. R050f v2 battles without extra commands skip command stages and rely on task/final criteria review; missing required runtime evidence blocks completion, never counts as a passing test. Restart never replays unfinished effects; full reconciliation and sleep/resume remain open.

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

R050c uses that same native helper to inspect a retained preparation's ownership,
locked detached registration, index and raw tracked bytes. It does not execute
provider turns or project checks, modify files, or allocate runtime resources.
Dated observations require fresh validation at future execution admission.

The first runner is a supervised host process runner using Git worktrees.
There are no containers, remote workers or claimed host sandbox boundaries.

The target Arena exposes one **Start** action. Ordinary owned worktree creation,
fresh inspection and stage dispatch belong to that bounded battle authority;
users should not prepare every checkout manually. Current preparation/inspection
utilities remain in Advanced and do not authorize a battle. Folder analysis is
read-only planning and requires neither Git initialization nor an execution grant.
See [D022](DECISIONS.md#d022--simple-arena) and [Flow](FLOW.md).

## Owned execution

R020r Cursor initial planning shares the isolated ACP runtime with a separate
no-tools operation. It has a two-minute native bound, one prompt and no host file
service or Arena cwd. Only frozen snapshots/brief are input. Main helper polling
can cancel while its bounded writer thread owns a blocked stdin pipe; group cleanup
still precedes private-store removal. Exact runtime model/parameters and explicit
cleanup survive normalization. Planning never grants task execution or session
continuation, and real account/physical interruption acceptance remains open.

R060k makes normal native group closure explicit: TERM/KILL while the owned
leader remains unreaped, finite exit/group-disappearance waits, then a cached
verified/uncertain receipt. A lost leader cannot authorize another signal.
Elixir preserves false or malformed closure through provider normalization and
cancellation; neither can become work/authorization success. Private Cursor
runtime stores are removed only after verified closure. This checks the owned
group, not escaped sessions; missing receipts and crash reconciliation remain open.

R060l closes only the completed-provider/lost-reply gap for new Start policies.
Native task launch reserves an exclusive intent bound to attempt digest, exact
connection, provider executable identity/model/effort and UUID scratch path. Evidence
stays in a separate private `provider-closures/<UUID>` directory; runtime scratch
remains empty at launch and its grant cannot read the closure files. After
verified closure it fsyncs public closure metadata before replying. Restart may
repeat the fixed bounded read, never a provider turn or signal. SQLite retains the
observation separately; it permits confirmed Stop and connection-capacity release,
not task acceptance, head movement, Resume, Retry or Skip. Late observations cannot
extend deadlines. Missing/partial receipts, escaped processes, killed helpers,
uncertain Cursor stores and broader native/process/port recovery remain open.

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

R060a implements Pause at a completed stage boundary. Existing bounded workers
are allowed to finish, then their receipts and verified cleanup commit with
Paused. Resume never restores a native process or reruns that stage; it opens
admission to the next stage under the unchanged Start snapshot/deadline. Native
ownership/grant checks still precede effects. Clean paused battles survive
restart, while interrupted Pausing requires inspection. This is separate from
the broader crash/sleep reconciliation target below.

R060d recovers running/pausing checkpoints to Paused when all attempts are settled
with verified cleanup; no stage is launched at startup. Resume is explicit and
uses existing native ownership/ref/grant checks under the original deadline.
Unfinished claims, missing cleanup and uncertain Stop still require inspection.
No process is inferred dead, reattached or replayed by this checkpoint recovery.

R060h adds a conservative timing fence for new `elapsed-gap-v1` grants. BattleClock
runs independently of the coordinator inside its one_for_all execution group.
UTC/monotonic samples detect five-second gaps, backward clocks and two-second
divergence. Record the observation before closing admission. Clean checkpoints
pause for explicit Resume; active work is cancelled through existing helper
polling and its rejected receipt retained. Verified closure allows Stop only;
uncertain effects still require inspection. A lost clock guard stops old workers
before baseline reset. Observed gaps do not prove sleep, and no stage/deadline/
consumed limit is restarted. Physical wake/lease/process reconciliation and
active-time accounting below remain open.

R060i implements the native idle-sleep assertion for new `shell-lease-v1` Starts.
Phoenix requests it while a running battle remains within its original deadline,
or an ordinary Pausing stage is still within both deadlines. Stop/timing
cancellation has at most five seconds of cleanup eligibility, also bounded by
the original deadlines plus that grace. Paused/attention/finished battles and
historical snapshots do not renew it. Each authenticated shell heartbeat replaces
the owned assertion with a fixed 15-second PreventUserIdleSystemSleep assertion;
the OS turns it off without renewal and keeps its ID reserved until release.
The next heartbeat releases it when work becomes ineligible. Quit/error/drop
also release it. Release failure retains the handle rather than accumulating
assertions, and the timeout still bounds its effect. API failure does not close
the app. Settings shows only the last normalized native report with its age;
it does not certify current protection. No display, lid/forced-sleep, wake or
deadline-extension capability is added. Source UI development has no native lease.

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

## Retained task candidates (R050d1)

The fixed native Git service can capture at most 64 eligible task paths, 32 KiB
each and 512 KiB total, with exact SHA-256 values supplied by the host. It reuses
R050c ownership/registration validation and descriptor-relative reads. An isolated
candidate index starts from the prepared base; raw blobs bypass filters. Unlisted
tracked bytes, file modes and all extra entries are checked against the resulting
tree. Hidden/protected task paths, symlinks/hardlinks, deletions and changed modes
are refused. This intentionally matches the first task-tool grant.

`runtime-home/worktrees/<worktree UUID>/candidate-<command UUID>/` retains exclusive
intent, candidate index, publication intent and completed receipt. A successful
capture retains `refs/ccoding/candidates/<command UUID>` with an absent-ref
compare-and-swap. It never moves source/task HEAD, touches their indexes or merges
the user's branch. Existing refs/locks and partial effects remain intact.
Verification rechecks the exact receipt, app ref, tree, ownership and live bytes.
These R050d1 primitives are now used by R050e Start, project checks and Secutor.
Candidate capture alone provides no review or completion authority. Interrupted capture is inspected with
retained evidence, never replayed under the same key.

## Explicit role pairs (R070e)

A required role may assign a second named connection/model through Team. Both
instances use existing host-task grants, separate attempts/sessions/worktrees and
exact native profile locks; no authorization store is cloned. Start freezes all
pairs, and deterministic task slots never select another runtime when busy or
unavailable. Primary-only planning, final stages and configured command checks
retain their existing grants. Native admission/Resume checks include every extra.
Fixtures establish allocation/control behavior, not real-account concurrency.
