# Sequential Arena execution — implementation decision

R060r new Starts freeze task-local continuation. A validated provider `blocked`
receipt or exhausted task Secutor review can hold that task while ready independent
tasks continue, after every current worker verifies cleanup. Blocked prerequisites
never unlock dependents. All unresolved tasks must receive explicit decisions
before final review/completion; Skip still produces reviewed Partial output.
Shared, uncertain and final-stage failures close the Arena. User Pause/restart
need explicit Resume, with the original deadline, bindings and counters unchanged.
Older Starts keep their failure behavior; schema eighteen fences older bundles.

R060o adds fixed retained-candidate recovery. New Starts freeze
`candidate_recovery: retained-candidate-wave-v1`. One/two exact interrupted
captures or a mixed capture/preparation pair queue exclusive supervised reads.
The native read requires original intent/publication/receipt, exact files,
preparation/battle tag and current source/ref/owned bytes. Missing evidence is
never rebuilt; no capture/provider turn repeats. Each observation is separate
from its immutable Interrupted attempt. All members must verify before one
atomic Paused checkpoint, with unchanged slots/bindings/budgets/deadlines.
Expired/fenced reads permit verified Stop only. Other native/provider/sleep
recovery remains open. [Decision](DECISIONS.md#d046--recover-complete-retained-candidate-checkpoints).

R050h adds version-four workflow stages with explicit read/write access and
before/after Implementor placement. Start freezes `write-role-stages-v1`; prior
read-only/missing policies never acquire write authority. `Battles.Stages` owns
order/access/continuation; `Battles.Writers` reads bounded immutable successful
writer attempts for the exact task/preparation and folds cumulative final hashes.
Every writer captures an immutable candidate before the next role; later turns
verify that checkpoint. The original worktree/head/index and source checkout stay
unchanged by capture. Independent task/final review and serialized integration
remain mandatory. Writer retry starts fresh preparation/Speculator; interrupted
captures remain inspection gates. No native operation or runtime tool is added. The seventeenth migration
indexes writer evidence and blocks older bundles before authentication/dispatch;
back up first. [Decision](DECISIONS.md#d045--explicit-custom-writer-checkpoints).

R050g extends R030d only for explicitly selected custom read stages. A version-three
board definition may insert up to four ordered custom roles between Speculator
and Implementor. New Starts freeze `custom_stages: read-role-stages-v1`, the full
workflow and only the selected additional bindings. Each stage runs through the
existing supervised executor/read grant, exact connection capacity and lifetime
budgets. The Speculator plan is retained alongside ordered findings (512 bytes
each); no edit receipt or changes-requested completion is accepted from them.
Pause/Retry/Stop and retained provider closure still apply. Task/final Secutor
reviews remain independent after writing. Historical snapshots without this
policy gain no stages; R050h extends newer workflows without rewriting history.

R030d binds the four required execution responsibilities from the exact saved
team revision before resolving native connections/models. Extra custom planning
roles stay in the saved team and task-generation selector; their unused bindings
cannot block Start or gain a battle session. Start Inspect lists them as planning
only. Required role order/membership, default columns and every existing admission/
review/check gate remain enforced. Old battle snapshots are never rewritten.

R050e keeps SQLite authoritative. A battle freezes the existing board's bounded
task graph, immutable team/model bindings, source folder identity, committed Git
base, user-declared checks and finite lifetime limits. The Start form fingerprint
is invalid after scope changes. No provider text can expand this snapshot.

One supervised worker advances durable stage attempts. A recorded intent and
claim precede every external action; an exact matching result and event commit
before the next action. Restarted or uncertain attempts need attention and are
never replayed automatically. Stop closes admission immediately and waits for
the existing native cancellation/cleanup receipt before showing stopped.

R060a adds **Pause** and **Resume** on this board. Pause immediately blocks new
claims while the already-claimed stage finishes under its original deadline.
Its matching result must verify cleanup before Paused appears. Failure, review
exhaustion or uncertainty takes precedence; final summary completion ends the
battle instead of pausing it. Stop can cancel while Pausing.

Resume uses a fresh session-bound control revision and the same frozen team,
criteria, stage, review counters, consumed turns and wall deadline. Paused time
counts toward that deadline. Exact connection observations must still match;
native effects retain their existing worktree/ref/executable validation. There
is no revived provider session, repeated completed stage or implicit new Start.
Clean paused boundaries survive app restart; interrupted Pausing remains
needs-attention. Full crash/sleep reconciliation remains open.

R060d extends this to running/pausing checkpoints where every prior attempt is
settled with verified cleanup, including failures already consumed by Retry/Skip.
Startup records `battle.recovery_paused` and a new control revision, then waits
for explicit Resume at the unchanged stage. No attempts, native effects or
provider calls are repeated. Existing pauses remain unchanged on repeated startup.
Unknown cleanup, unfinished claims and interrupted Stop still require inspection.
Original deadlines include downtime; Resume cannot reset exhausted authority.

R060e retains a valid late stage receipt as **Expired** with an explicit
not-accepted label in Inspect. Normalized edits, check results, native receipts
and cleanup status remain immutable, including host cancellation on deadline.
No task completes and no review/head advances from this result. Stop can release
the Arena only after every attempt's cleanup is verified; missing or uncertain
receipts still block. Expired work cannot Resume, Retry or Skip, and no artifact
is deleted or automatically replayed. This is known-result closure, not recovery
of missing native receipts or physical sleep reconciliation.

R060f commits the validated outcome in the supervised stage worker before its
completion message reaches BattleRunner. If the coordinator crashes with that
message queued, startup retains the receipt and pauses the saved next stage for
explicit Resume. Missing or uncommitted results still require inspection. Stop
can close a race with a finished stage only when its exact result validates and
verifies cleanup; malformed/foreign flags cannot establish cleanup or accept work.

R060g freezes `native_recovery: retained-integration-v1` in new Starts. A restart
interrupted at integration may verify the already-written native intent,
publication and receipt against the exact frozen request, current app ref,
candidate ancestry and owned worktree/source identity. This is a read-only
inspection in a supervised worker; no ref is moved and no receipt is recreated.
The original Interrupted attempt stays intact. A separate durable observation
advances a verified result once to Paused, requiring explicit Resume with all
original limits and bindings. If either original deadline passed, the verified
effect closes cleanup for confirmed Stop only; cards/head never advance.
Inspect shows the pending inspection and retained observation after reconnect.
Missing or mismatched evidence remains needs-attention. Historical grants,
interrupted Stop and other native/provider stages cannot use this path.

R060m separately freezes `worktree_recovery: retained-preparation-v1`. One
restart-interrupted writer preparation with otherwise settled history may read
its complete private receipt and battle tag under the same exclusive recovery
worker/repository lock. Exact source/ref/head and unchanged owned checkout are
required. Keep the Interrupted attempt and append a dated observation in Inspect;
verified in-budget evidence advances once to Paused for explicit Resume. Expired
evidence or a timing fence racing a completed read supplies Stop closure only.
Older grants, already-stopping/fenced claims, missing proofs and multiple unfinished
native stages gain no continuation. No checkout is created or receipt repaired.

R060n extends only new Starts with `worktree_wave_recovery: retained-preparation-wave-v1`.
Two interrupted writer preparations may queue the same exclusive fixed read.
Keep both tasks at preparation until both receipts and all original deadlines
verify; then save both next stages and one Paused checkpoint atomically. Resume
keeps their frozen worker slots. Failed, partial, mixed-stage, expired or fenced
waves cannot advance one task alone. Retain each known closure for Stop; an
unknown member still blocks it. Older Starts retain R060m's one-claim limit.

R060l adds the separate `retained-provider-closure-v1` policy to new Starts.
Codex/Cursor task helpers reserve an exact private intent before launch and fsync
public closure metadata before returning. After restart, a supervised read may
verify that retained closure without replaying any turn or accepting its work.
The original attempt, edits and frozen scope remain intact. Inspect shows the
pending/read result; verified closure permits confirmed Stop and releases that
exact connection's capacity, never Resume/Retry/Skip or task/head advancement.
Missing/partial/foreign files and killed helpers without a receipt remain blocked.
This is separate from continuing a native provider session or sleep recovery.

R060h freezes `timing_guard: elapsed-gap-v1` for new Starts. An independent OTP
guard checks UTC/monotonic samples before admission, throughout helper polling
and before worker settlement. A five-second elapsed gap, backward wall movement
or two-second divergence closes admission durably. These samples cannot prove
actual sleep. A clean boundary pauses for explicit Resume with unchanged scope,
bindings and deadline. Backward clock movement requires attention and a new Start.
An active stage cancels through its existing helper protocol; its exact bound
receipt stays Interrupted and rejected, even if it reports success. No card,
reviewed head or next stage advances. Stop requires recorded verified cleanup;
unknown cleanup remains blocked, and active fenced work cannot Resume/Retry/Skip.
The guard shares the battle execution group's restart boundary, so losing its
baseline also stops workers. Inspect retains timing observations after reconnect.
This is a conservative timing fence, not native wake/process/lease reconciliation,
active-time accounting or physical sleep acceptance.

R060i freezes `idle_sleep: shell-lease-v1` in new Starts. Eligible bounded work
requests a fixed native idle-system sleep assertion through the authenticated
shell heartbeat. Paused/idle work releases it; Stop/timing cancellation receives
at most five seconds of cleanup eligibility. The OS turns the assertion off
after 15 seconds without renewal, and its owned ID remains reserved until
explicit release. Power API failure is nonfatal. Settings displays dated native
reports, not current-protection or recovery proof. The display can sleep, and lid
closure/forced sleep still interrupt work. This changes no execution authority,
original deadlines, historical snapshots or independent-review gates.

R060b adds **Retry failed stage** for new snapshots with `recovery: provider-retry-v1`
and a frozen two-retry cap per task, plus two shared by final stages. Only normalized
launch/timeout/connection/provider/busy/turn failures with verified cleanup qualify.
Retry is explicit and can consume provider allowance. It records the failed attempt
ID before admitting a new attempt/session; the old request, receipt and edits stay
immutable. A failed Implementor goes through fresh worktree preparation, Summa Rudis
and Speculator from the last reviewed head. Read-only roles retry the same stage
with existing native integrity checks. Criteria, reviewed head, review rounds,
consumed turns and original deadline do not change. Failed reviews, policy/model
drift, native-stage errors and interrupted/uncertain work cannot Retry. Historical
snapshots without this contract remain unchanged. Successful retries preserve
Pause/Resume; failed attempts remain visible in Inspect.

R060j freezes `provider_backoff: automatic-provider-backoff-v1` in new Starts.
Only eligible `connection_lost`, `profile_busy`, `timeout` and `launch_failed`
failures automatically wait 5 seconds for the first retry and 20 for the second.
Generic provider/turn errors remain manual. SQLite retains the failed attempt ID,
schedule and due time; the coordinator releases its worker while waiting.
Due admission rechecks exact eligibility, bindings, original limits and deadline
under the write lock, then uses the same R060b transition and a fresh claim.
Cancel automatic retry leaves the settled failure available for inspection/manual
Retry. Stop, Skip and timing fences cancel the wait; startup cancels it before
admission and never repeats a provider call. Old snapshots gain no automatic
authority, and failed writers still start fresh from the reviewed head.

R060q new Starts use backoff v2, adding only explicit Codex overload to automatic
retries with bounded per-attempt 5–7/20–22-second jitter. The two-retry cap and
all existing admission/cleanup/drain gates stay unchanged. Usage/session limits
do not retry; ambiguous HTTP 429 remains manual. Native willRetry notifications
stay within the original bounded turn; historical v1 retains its exact behavior.

R070a freezes `scheduler: isolated-arenas-v1` in new Starts. Two isolated Arenas
may have supervised stages in progress concurrently, with one stage per battle
and one provider turn per exact saved connection. SQLite checks capacity before
inserting the attempt; waiting spends no turns/retries. Failed/interrupted
provider work without verified cleanup keeps that connection reserved. The
coordinator rotates ready Arenas fairly and ignores paused/backoff work until
eligible. Old Starts and retained integration inspection dispatch exclusively.
Restart stops all old workers before recovery; Stop/Pause affect their own Arena.
Each board still has sequential tasks and serialized reviewed integration;
same-board parallel writers and combined-candidate review remain open.

R070b supplies the native combination prerequisite, not parallel dispatch. A
captured writer must retain its exact battle/worktree origin. The fixed operation
rebuilds compatible bounded file changes on the current reviewed head using Git
objects and a private index, without a project merge driver. Divergent overlap or
case/file-directory collisions return `candidate_conflict`; old edits remain.
An exclusive intent/publication/receipt and UUID ref bind both bases and candidates.
Missing evidence cannot be repaired by replay. A new independent review/check
checkout contains the combined tree before existing serialized CAS; native success
alone never completes a task. Combined operations/consumers use a fixed 60-second
native budget and 65-second host ceiling; existing sequential limits and active
cancellation remain. Future lane stages must also retain their original deadlines.

R070d freezes `parallelism: parallel-waves-v1` in new Starts. SQLite selects up to
two independent ready tasks whose prerequisites are already integrated. Each owns
its stage, workspace and fresh sessions. Two global workers and one provider turn
per exact connection remain; different assigned bindings permit overlap, while
shared role connections queue. Old snapshots stay sequential.

The wave finishes implementation/capture before serialized checks, Secutor review
and CAS. A later candidate based on the old head uses R070b combination, clears old
check/review authority and obtains fresh independent evidence. A verified conflict
consumes a review round and returns through a fresh coordinator/Speculator/writer;
its failed attempt/edits remain immutable. Other native failures never replay.
Pause drains all current stages. Stop and timing fences require every bound
cleanup receipt, without renewing the original five-second cleanup sleep window.
Failures drain siblings before attention; each failed lane has its own Retry/Skip
choice. Automatic backoff waits for a clean ordinary drain; multiple unresolved
failures and user Pause remain explicit. Late siblings retain rejected receipts
without head/card advancement. Startup interrupts every unfinished claim and may
queue exact provider-closure reads individually; these allow Stop/capacity release
only, never continuation. VM repository queues are not cleanup evidence.
R070e adds assigned role pairs below. Interrupted native sessions, real-provider and
physical-sleep acceptance remain open. [Implementation](../tasks/R070d-parallel-waves.md).

R060c adds **Skip task** under `task_selection: skip-task-v1`. A clean paused task,
settled provider block/transient failure or exhausted task review may be skipped
after confirming its exact ID/control revision and affected dependent tasks.
Verify all worker cleanup, original limits and current bindings. Native/policy
failures, active/interrupted workers and final stages cannot be skipped. The host
atomically records `battle.task_skipped`, marks the task skipped and transitive
dependents deferred, retaining original drafts, snapshots, attempts and edits.
Independent work starts from the last reviewed head; paused battles stay paused.

Final checks and independent Secutor review cover the retained subset; the final
criteria digest includes explicit omitted task IDs/statuses. Prompts name omissions
as unfinished. The final state/event is `partial`/`battle.partial`, never completed.
Partial is terminal and releases Arena locks. If no task completed and all are
omitted, stop without final inference. Nothing deletes or integrates abandoned edits,
resets budgets, retries a native effect or grants historical battles new authority.

The host offers Summa Rudis a single closed next-stage decision. Speculator
prepares public instructions without dropping frozen criteria; Implementor has
bounded host file tools; Secutor uses a separate read-only session and exact
candidate/check evidence. Rejections return through Speculator within the original
budget. Product concurrency is one task at a time in this first implementation.

Native host Git operations retain candidates and advance only a UUID-derived
app battle branch with compare-and-swap. Every next task starts from that reviewed
head in a new owned worktree. The user's checkout, index and branch are preserved.
Final verification and a separate final Secutor assessment precede completion.

Project checks execute only frozen user-authored literal argv under a verified
host grant, empty inherited environment, finite timeout and owned cleanup.
Unsupported command restrictions must block rather than run with broader access.
Provider tools never receive a shell or network grant. No dependency is added.

This decision introduces battle and attempt records plus a supervised executor;
existing setup/planning commands and read-only Battle preview keep their meaning.
No push, PR, user-branch merge or deployment is part of Start authority.

## Task verification (R050f)

Create tasks asks Speculator for expected outcomes and concrete verification
instructions from the supplied specs, stored in the existing revisioned `criteria`
field. Start freezes them with the task graph. No separate command setup is needed.
Secutor reviews every frozen criterion on the exact candidate, then independently
reviews all criteria on the combined result. Required runtime/test evidence that
cannot be obtained under the actual grant blocks completion; inspection is not a
test run. Existing cards and their criteria are never silently rewritten.

New `arena-loop-v2` snapshots with no configured extra commands go from capture
directly to Secutor and from final integration directly to final Secutor. No
command resolver/runner is called and no passing command receipt is created. A completed
review also requires a successful host file-inspection tool receipt; a report
with no inspection cannot pass.
The frozen scope and Start event retain version and command count. Historical
`arena-loop-v1` snapshots do not gain this exemption. Any explicitly configured
commands remain mandatory, candidate-bound gates with the existing correction
loop. Commands remain optional Advanced settings, not generated executable policy.

## Initial supported scope

Default columns and the four required roles, bound independently to named Codex or Cursor connections.
An unchanged successful catalog observation and exact selected executable/model
remain required at each role turn. R080a permits an aged saved binding; native
account/model checks still run before dispatch. Failed/invalidated observations
still refuse use. Every Codex role needs `0.162.0-alpha.17.2` or `0.163.0-alpha.11.2`; Cursor roles need
`2026.09.15-d2fe57e` and the verified `cursor-acp-v1` grant. Extra command checks
still require the Codex Implementor runtime. No fallback or implicit account/model substitution occurs.
At most 20 tasks, three review returns per task, 200 role stages and two wall-clock
hours; each stage expires after at most 15 minutes. Prompt preflight reserves
worst-case public summaries and check metadata without truncating frozen criteria.

Start uses the original source's current committed HEAD, inspected at admission;
unsaved/untracked source files are not copied into execution. Missing Git/initial
commit uses the existing explicit Advanced controls. After completion or verified
Stop, a new Start uses the current original committed source again; it does not
silently adopt a previous battle branch. Frozen task edits are refused during an
active/uncertain battle; newly added tasks wait for a future battle.

## Checks and process ownership

New Starts whose explicitly saved check list contains only `npm`/`mix` freeze
`isolated-guest-checks-v1` and the compiled image specification. The existing
admission task installs pinned toolchains on first use or verifies a completed
admission's exact image; this is part of Start, not an extra setup screen.
Each check uses a single-use native run, an immutable committed-candidate capsule
and offline Linux VM. Literal arguments/directory/timeout and exact attempt,
candidate, capsule and image hashes bind its receipt. Both native VM Stopped and
owned helper cleanup must verify. A failed test goes to Secutor, then a fresh
Speculator/Implementor correction within the original review budget. Secutor and
final Secutor validate the original completed check attempt and candidate before
acceptance. Unverified admission/check closure reserves global capacity and needs
inspection; missing processes cannot release it. Pause still drains the current
stage, and Stop cancels through the same owned Port. No provider inference or new
provider tools are used to run the checks.

The image includes fixed Node/npm/OTP/Elixir, no project dependency download or
host shares/network. Linux results do not establish macOS/browser equivalence.
Automatic task-proposed commands and retained failure-log delivery remain open.
Mixed system/guest lists refuse before effects; older snapshots keep their grants.

The historical system grant is `codex-check-single-process-v1`. Resolve only native executables
in `/usr/bin` or `/bin`, freeze identities and literal argv, then run through RTK
inside the verified Codex CLI sandbox from an empty private profile. Each check
has a maximum 300-second timeout; combined declared timeouts may not exceed 600
seconds. Scripts, subprocess toolchains, Mix/npm pipelines and dependency installs
are unsupported by that grant. No account or model is used to establish the command sandbox.

A trusted inner supervisor creates one direct child, which becomes a session
leader and applies a hard zero process limit before executing project code. A
pre-exec barrier waits until the host journals its identity and confirms kernel
audit-token access. Normal cleanup owns the unreaped child; if a check kills its
supervisor, fallback signalling uses a fresh kernel audit token after checking
the original start identity. Numeric PID lookup alone never authorizes a kill.
The command cannot fork or leave its session. The outer runtime group is cleaned
separately. Cancellation/timeout retain partial receipts and cleanup uncertainty. Existing candidate file bytes/modes must remain unchanged in the
verification copy; new output files there do not enter the candidate. Network and
protected policy/credential paths are denied. Output is bounded and hashed; raw
command output is not stored or sent to a provider in this first grant.

Ordinary nonzero check exits go to independent Secutor review. A passing verdict
is impossible while a declared check failed or was skipped. Actionable findings
return through Speculator within the original review budget. Infrastructure errors,
uncertain cleanup and final combined-review rejection need attention.

## Evidence and remaining acceptance

Adapter fixtures exercise a two-task dependency chain with a forced check/review
return, fresh correction checkout and final review. Native tests separately verify
Git preservation, sandbox behavior and process lifetime. These do not substitute
for a live signed-in two-task battle. Full restart/sleep
reconciliation, real-provider parallel/custom-stage acceptance, task-proposed checks,
dependency/platform support and remaining providers stay open in [Plan](PLAN.md).
No additional application dependency is added.

## Cursor role turns (R020p)

The native adapter runs ACP in an empty owned directory and denies native tools.
Model JSON may request only the existing bounded host file operations. The exact
CLI alias comes from the current catalog; Cursor resolves its own base model and
parameters, which must match the ACP session before and after prompts. Both are
retained in the public receipt. No alias rewriting or default-model fallback.
One role stage is capped at five minutes, 64 host operations and 65 model prompts;
these prompts may consume provider allowance. Stop/timeout retain existing edits
and terminate the owned group. No failed stage is automatically replayed.
Cursor can fill any battle role; R020r also enables initial Create tasks through
the assigned Cursor Speculator with no runtime/host tools and frozen snapshots.
Runtime session files are private and removed after cleanup; hard process death
can leave them for recovery. Raw thought frames never enter application receipts.
Protocol fixtures and real metadata-only model selection checks pass. Live Cursor
read/edit/denial and mixed-battle acceptance remain open; see the R020p worklog.

## Assigned role workers (R070e)

Team exposes one optional additional exact agent/model for each required role.
Saving launches nothing and existing boards still adopt defaults explicitly.
New Start freezes `assigned-pairs-v1`, primary roles and all configured extras.
Wave lane 0 uses primaries; lane 1 uses each configured extra, or the saved shared
primary where none is configured. A present invalid/disconnected extra blocks
Start/Resume; a busy one waits. No credential copy, implicit promotion or fallback.

Each task retains its allocated slot across review repair/Retry. With extras,
earlier pipeline stages take priority so shared planning turns can finish before
writers occupy their connections. The two global workers and exact-connection
cap remain. Final stages/configured command checks use the primary binding.
All frozen bindings block Disconnect while unfinished; afterward Disconnect
unassigns that exact connection in both current positions and all current scopes.
Older Starts keep their bindings/ordering. Real-provider acceptance is separate.
