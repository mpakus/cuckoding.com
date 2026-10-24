# Current decisions

## D039 · Parallel implementation waves with serialized review

Accepted before implementation, 2026-10-21, R070d. New Starts freeze a two-task
wave policy, retaining the two global stage slots and one provider turn per exact
connection. SQLite claims only independent tasks whose prerequisites are already
integrated; each task owns its stage, worktree and fresh provider sessions.
The reviewed head stays fixed until every wave implementation/capture settles.
Checks, Secutor review and integration then run serially. A later task based on
the old head must use the retained combined candidate and new independent review;
overlap returns through bounded fresh-worktree specification/implementation repair.

Native repository I/O is serialized in supervised workers with bounded cancellable
waiting; VM coordination is never native ownership, effect or cleanup proof.
Pause drains all workers and Stop waits for all exact cleanup. Failed waves drain
their current bounded stages before attention; each failed task keeps its own
explicit retry/skip authority, lifetime budgets and immutable evidence. Recovery
and timing fences retain every interrupted claim without replay. Old frozen
policies keep their original sequential dispatch and controls. No new provider
tools, account fallback, credential cloning or real-account acceptance is granted.

## D038 · Validate outcomes against the immutable attempt

Accepted before implementation, 2026-10-21, R070c. Keep closed receipt/envelope,
provider identity/session, candidate/check and historical-policy validation in
`Battles.Receipts`. The durable battle owner invokes that boundary inside its
existing transaction for settlement, Stop, expiry and recovery. The validator
reads retained attempts only for session reuse; it never writes, launches work or
selects a task from a mutable coordinator cursor. Reuse this single boundary for
the upcoming lane workflow, rather than copy the sequential validator.
This extraction changes no grants, budgets, projections or Start policies.

## D037 · Rebuild parallel candidates on the reviewed head

Accepted before implementation, 2026-10-21, R070b. Native combination validates
the retained task candidate and current battle ref under the repository lock,
including ancestry from the battle base. Build an isolated index on the reviewed
head and apply only compatible bounded captured path changes. An overlap or file/
directory/case collision is a conflict for workflow repair, never a last-writer
overwrite. Use raw Git object/index operations, not merge drivers or project
commands. Retain exclusive intent/publication/receipt and a UUID-owned candidate
ref; partial effects never replay. The new single-parent candidate needs its own
check/review checkout and independent Secutor verdict before serialized CAS.
This primitive does not authorize parallel lanes, custom stages or a new Start;
those require their own frozen workflow, SQLite capacity and control contracts.

## D036 · Scoped team edits append without changing defaults

Accepted before implementation, 2026-10-21, R030c. Reuse the existing Team editor,
immutable team revisions, command ledger and scoped adoptions. An explicit scoped
Save appends the role definition, its exact scope/revision command, adoption and
event together. New `save_scoped_team` and `disconnect_scoped_agent_roles` commands
distinguish scoped-only revisions from defaults; the default projection excludes
only those kinds. Keep old revisions/commands and their historical default-restoring
disconnect behavior readable without rewriting them or adding a second pointer.
Scoped edits affect future work and new-board inheritance only, never existing
planning/battle snapshots or sibling boards. Bind the editor to a validated scope
at mount, retain dirty text, and reject navigation/form drift instead of falling
back to the default editor. Saved-default adoption stays separately explicit.

## D035 · Dashboard observations stay read-only

2026-10-21, R080g. Global and Arena dashboards derive bounded views from retained
SQLite facts; no process cache, page load, follow toggle or link owns execution
authority. Public worker bindings and event metadata are sufficient for ordinary
activity; raw provider/event payloads stay excluded. Direct Arena scope wins over
board/command references, without foreign-scope fallback. Page/follow/scroll state
is transient UI state in session-guarded LiveComponents. Retain twenty-row pages,
stable reading and explicit follow-latest; keep task evidence and controls on the
existing exact board. Index-only forward migrations preserve older facts.

## D034 · Concurrent isolated Arenas

Accepted before implementation, 2026-10-21, R070a. New Starts freeze
`scheduler: isolated-arenas-v1`. Admit at most two battle stage workers globally,
one per battle/Arena and one provider stage per exact connection. Enforce these
caps in the SQLite claim transaction before creating an attempt; busy capacity
queues work without consuming retry/turn budgets. Fair rotation across ready
Arenas is a coordinator cache only; claims/receipts remain durable authority.
Historical Starts and retained integration inspection run exclusively. Keep the
one_for_all clock/tasks/coordinator group so restart stops every old worker before
checkpoint recovery. This does not enable same-board parallel task writers,
combined-candidate integration, toolchain spawning or new provider permissions.

## D033 · Bounded automatic provider backoff

2026-10-21, R060j, accepted before implementation. New Starts freeze
`automatic-provider-backoff-v1`; only R060b-eligible settled `connection_lost`,
`profile_busy`, `timeout` or `launch_failed` provider receipts with verified
cleanup may wait 5/20 seconds and consume the existing two retries
per task/shared final scope. SQLite stores the exact failed attempt and UTC due
instant; no sleeping worker, native replay, new budget or provider fallback.
At due admission, revalidate bindings, limits and exact eligibility under the
write lock, record the existing retry transition and claim a fresh attempt.
Writer retries still start with a fresh worktree/coordinator/Speculator.
Historical snapshots remain manual. Startup cancels a pending automatic wait
before admission; explicit Retry remains possible after inspection. Cancel/Stop
retain revisions/session/form guards and every failed edit/receipt. UI discloses
provider allowance and the bounded wait within the original wall deadline.
Generic provider/turn errors remain manual because their cause is unknown.

## D032 · Local disconnect when native logout is unavailable

Accepted 2026-10-15 for R080b. The roster's confirmed Disconnect first uses the
existing verified native logout. If executable verification is unavailable,
reuse the SQLite command/event and current-role unassignment transaction to
disable only that saved connection locally. Do not launch an unverified program,
delete its provider-owned profile, infer logout or substitute a connected peer.
Store a closed local-only receipt and unknown provider authorization; explain
that provider sign-out was not attempted. Battle exclusion, global setup busy,
session/form and workspace-revision guards still apply. Historical commands,
team revisions and frozen battle bindings stay immutable. Replaying one accepted
local command returns its receipt without repeating effects.

## D031 · Native idle-sleep lease

Accepted 2026-10-15 for R060i. New Starts freeze `idle_sleep: shell-lease-v1`.
Phoenix derives work eligibility from SQLite battle/attempt state, original
deadlines and a five-second cancellation grace. The existing authenticated shell
heartbeat returns only a fixed boolean/15-second lease contract. The shell owns
one timed PreventUserIdleSystemSleep assertion, with explicit OS timeout TurnOff,
and releases it on idle/pause/quit/errors/drop. It cannot keep the display on,
wake the Mac or prevent lid/forced sleep. No agent text controls this capability.

Native assertion failures are nonfatal. The authenticated shell reports only
held/released/unavailable; persist state-change observations, not heartbeat spam
or raw OS errors. Settings shows the last transient report with freshness and
explicit limits; age uses both UTC and monotonic time and distrusts backward
time. It is not workflow authority or proof of current power state.
No renewed heartbeat means the assertion turns off within its fixed lease.
Physical sleep, process reconciliation and active-time accounting remain open.

## D030 · Conservative timing-gap fence

Accepted 2026-10-15 for R060h. New Starts freeze
`timing_guard: elapsed-gap-v1`. A dedicated supervised clock guard observes UTC
and monotonic samples, independently of the battle coordinator so workers can
still commit outcomes while its mailbox is suspended. The guard shares the
battle execution group's restart boundary. It checks before admission, during
bounded helper polling and before settlement; SQLite owns every resulting fence.

A gap of at least five seconds, backward wall time, or UTC/monotonic divergence
of at least two seconds triggers a bounded public timing observation. This is
not proof of sleep. Pause a clean settled boundary for explicit Resume; backward
clock movement requires attention. Close admission and cancel an active stage
through its existing helper protocol, retain its bound rejected receipt without
advancement, and permit Stop only with verified cleanup. Preserve deadlines,
consumed limits and interrupted history. A guard crash restarts the execution
group; it cannot silently reset the baseline while workers keep running.

No power assertion, physical sleep proof, process/lease reconciliation, resumed
native session, automatic retry or active-time accounting is implied.

## D029 · Retained integration reconciliation

Accepted 2026-10-15 for R060g. New battle Starts freeze
`native_recovery: retained-integration-v1`. After restart, only an interrupted
integration may inspect its exact durable native intent/publication/receipt under
the existing repository lock. Revalidate source identity, app ref, candidate
ancestry and owned worktree integrity; never repeat the mutation or manufacture
a missing receipt. Run inspection in the supervised battle worker, outside DB
transactions and coordinator callbacks.

SQLite retains the interrupted attempt unchanged and appends the normalized
observation with an atomic guarded transition. Verified outcomes within both
original deadlines advance exactly once to Paused, requiring explicit Resume.
Late verified effects may close cleanup for Stop but cannot advance. Failed or
missing evidence stays needs-attention. Historical snapshots, interrupted Stop,
provider stages, uncertain native publication and sleep/lease recovery retain
their existing gates. This extends checkpoint recovery, not general crash recovery.

Accepted product reset: 2026-10-06. Earlier ADRs remain in Git history; they do
not establish implementation or acceptance of this rebuild.

| ID | Decision | Reason / consequence |
| --- | --- | --- |
| D001 | Keep Elixir/OTP, Phoenix LiveView/Tailwind, Ecto/SQLite, Git worktrees and Tauri 2 | User requested the same stack; no replacement frontend/control plane |
| D002 | Arena = project, Tabula = board, battle = execution, Tabula Gladiatorum = global/Arena dashboard | One consistent product vocabulary; Area interpreted as Arena |
| D003 | Speculator → Implementor → Secutor; distinct Summa Rudis coordinator | Separate planning, writing, completion judgment and coordination |
| D004 | One Start action authorizes bounded ordinary local work | No competing manual/prepared/project start modes or repeated task approvals |
| D005 | Phoenix validates agent proposals; SQLite owns durable state | Model output cannot command the host or fabricate completion |
| D006 | Parallel task workers; serialized reviewed battle-branch integration | Deliver concurrency without shared writable worktrees or stale-review acceptance |
| D007 | One active battle per Arena initially | Keeps integration ownership simple; independent Arenas/tasks still run concurrently |
| D008 | Ordered custom columns/roles with mandatory final review | Meet extensibility need without a general workflow graph editor |
| D009 | Readable Markdown specs/evidence, scoped file search, RTK and Ponytail full | No XERJ, embeddings service, plugin marketplace or autonomous memory pipeline |
| D010 | Source reset preserves old application data; use a separate rebuild data root | No inferred permission to destroy databases/profiles/worktrees |
| D011 | Ten minutes from first launch to ready with runtime/account prerequisites stated | Measurable setup target; also report full installation timing |
| D012 | Provider capabilities require per-version real evidence | Named runtimes are targets, not unsupported promises; transport stays adapter-specific |
| D013 | Append-only scoped team adoptions override creation defaults for future work | Explicit confirmation and revision guards; Arena changes affect new boards, Tabula changes affect new planning, historical receipts stay unchanged |
| D014 | Explicit selected-document snapshots feed the existing no-tools planning turn | Local preview reads bounded text using pinned descriptors; separate provider consent freezes the scoped snapshot reference. Documents are untrusted evidence, never filesystem or execution authority |
| D015 | Draft prerequisites live in immutable draft revision content | Reuse the existing save transaction and current-revision projection; validate same-board references and acyclicity before saving. No scheduler or new execution authority is implied |
| D016 | New Speculator proposals reference earlier tasks and selected snapshots by bounded indices | A versioned contract binds references to the frozen request; import resolves prerequisites through same-board receipts and retains source provenance. No arbitrary path, task ID or execution authority comes from provider output |
| D017 | Accepted specs freeze task and prerequisite revisions before writing private Markdown | Reuse durable command receipts and draft history. Verify the file and revisions before atomic acceptance/ToDo; keep stale or interrupted artifacts, never overwrite or auto-replay them. Acceptance grants no execution |
| D018 | Save approved check declarations as immutable Arena revisions before battle execution | Explicitly preview literal argv, relative working directory and timeout; confirm changes/removals and audit atomically. Configuration never grants execution or proves a command safe. Future Start snapshots the revision and validates executable/worktree/runtime grants |
| D019 | Prepare detached locked worktrees through the existing consented Git ledger | Freeze fresh HEAD and folder identity before a fixed native operation. Keep ownership outside checkout, reject unsafe checkout mechanisms and bounded tree violations, retain interrupted effects. This is a setup utility, not battle admission or execution authority; Battle preview stays read-only |
| D020 | Inspect retained worktrees against their preparation receipt | Use the existing Git ledger to verify private ownership, detached locked registration, index entries and raw tracked bytes without mutation. Extra files are flagged without reading their contents. Built-in checkout transformations can report differences; this conservative dated observation is not execution authority or future cleanliness proof |
| D021 | Save independent named agent connections; retain legacy Codex identity | UUID-scoped profiles, commands, catalogs and selected models let each role choose its own agent/model. Keep the original `codex` projection/profile and immutable bindings readable; never fall back across connections. Setup stays serialized. Cursor setup does not enable inference |

| D022 | Add folder → Create tasks → Start on one Arena board | Reuse saved team, create the default board automatically, analyze bounded folder sources and create validated cards without mandatory per-card imports; one bounded Start covers ordinary work and independent review |

## D021 · Named local agent connections

Accepted 2026-10-10 for R020i.

An agent is a saved connection, not a global provider choice. Additional connections
have UUIDs, names, runtime kinds, version and account/catalog projections in SQLite.
Commands freeze that ID; native profiles derive from it, never a browser path.
The legacy `codex` ID keeps Workspace's existing projection and `agents/codex`
profile so old commands and immutable team bindings remain valid without rewriting.
The same domain API serves both. New role bindings retain the connection ID and
resolved model. No fallback to a different account, runtime or model is permitted.

The existing dispatcher remains globally serialized for bounded setup operations;
separate records/profiles do not claim parallel execution. Saved model selections
remain audited command snapshots, now scoped to connection ID. Cursor setup uses
only fixed version/status/models/login/logout commands in an app-owned file-backed
profile. Cursor inference/planning remains unavailable until its permission grant
is verified; saving a mixed team never grants execution.

The first release scope and deferred features are in [Product](PRODUCT.md).
[Flow](FLOW.md) owns state, defaults and limits. Changes to settled boundaries
must update this file before implementation and preserve the user-approved scope.

## D022 · Simple Arena

Accepted 2026-10-10 from the user's original story and Arena simplification.
Agents/Team are saved once. Adding a folder creates a default Tabula and opens it;
Create tasks uses the saved Speculator, an optional brief and bounded project
sources. Validated proposals become cards automatically. Start runs the same
board with Summa Rudis coordinating and Secutor judging completion. Advanced
holds additional boards, role/column configuration and technical inspection.

This supersedes mandatory separate Tabula/Describe/setup screens, not authority
or evidence requirements. D014's selected-snapshot implementation stays valid
until a versioned bounded folder-analysis contract replaces it. D017 acceptance
and D019/D020 setup utilities remain optional; battle admission still validates
fresh state. No routine per-task approval follows Start. Git initialization and
initial commit retain explicit consent when needed; read-only planning needs no Git.

Use existing Arenas/Tabulae/Planning contexts and command/event transactions.
No new frontend, queue or database. Add-folder/default-board persistence must be
atomic and idempotent; existing boards/history survive. Target automatic analysis,
card creation and execution remain open in [Plan](PLAN.md#next-delivery-order--simple-arena).

## D023 · Executable-bound isolation evidence

Accepted 2026-10-13 for R020m. Before enabling repository turns, verify the selected
Codex version's sandbox with fixed commands in disposable private fixtures. Use
the existing consented command ledger, executable identity and owned process
cleanup; retain only normalized check results. Explicitly deny temporary roots
and private profiles rather than assuming minimal-system access excludes them.
The optional Agents diagnostic does not touch an Arena, use an account/model,
or authorize work. Its success cannot substitute for a fresh battle grant,
effective thread policy, model tool validation or independent Secutor review.

## D024 — Host-owned task tools

Accepted 2026-10-13, before R020n implementation. The first coding turn retains
Codex's empty-scratch, built-in-tools-disabled grant and supplies only bounded
dynamic list/read/edit tools implemented by the host. This avoids giving model
text a general shell bridge. The host validates one frozen worktree identity,
relative eligible paths, byte/call limits and expected content hashes; protected
policy/credentials and other folders remain inaccessible. Tool effects retain
private receipts, while SQLite remains the attempt/authority owner. Independent
review receives only read tools. Host check declarations execute through a
separate bounded runner, never through proposed shell text.

This is actual file-tool execution, not a model response interpreted as a patch.
It supports the initial code-editing flow with finite text-file limits; commands,
binary editing and protected configuration are outside this grant. Full runtime
and two-workspace acceptance must still be measured, not inferred from schemas.

R020o clarifies the runtime routing layer after the first real task failed with
`code-mode host is disabled`. Task turns enable Code Mode and its process host,
a pure V8 interpreter forwarding the declared host-tool calls. It supplies no
Node/filesystem/network/import API. Shell, provider file tools, apps, MCP,
delegation and permission requests remain disabled/refused. No-tools diagnostics
and planning keep Code Mode disabled. Effective feature validation distinguishes
these grants; model text cannot turn routing into wider authority.

## D025 — Host-captured task candidates

2026-10-13. R050d1 extends the fixed native Git service with candidate capture and
verification. The host supplies exact bounded path/hash pairs from completed task
file-tool receipts; provider text never supplies Git argv or reference names.
A private candidate index preserves unchanged base objects. All other tracked
bytes and file modes must still match the prepared base; extra entries and policy
changes fail closed. Candidate objects and a UUID-derived application reference
are retained without updating the source checkout/index/branch or detached task
HEAD. An exclusive attempt directory records intent before effects; uncertain
attempts are inspected, never replayed. Verification compares the exact retained
candidate tree against live bytes. Start authority, check execution, independent
Secutor verdicts and reviewed integration are separate R050d/e responsibilities.

## D026 — Reusable saved roles and direct Arena controls

2026-10-14, R080a. Catalog age is a picker freshness signal, not an automatic
sign-out. Existing exact role bindings can reuse a successful observation after
24 hours; native account/model preflight remains required before dispatch. A
failed/invalidated observation still blocks, and changing model choices or running
an optional diagnostic still needs a fresh catalog. No fallback or new grant.

Confirmed Disconnect clears current assignments in the global default, Arenas and
boards through new immutable revisions before private logout. Historical team and
battle snapshots are preserved; unfinished battles using that agent refuse the
action. A failed logout leaves current roles unassigned. Reconnection cannot
silently restore earlier assignments.

Use one native dialog for on-demand forms. Create tasks, Repository setup and
Add another board are buttons; manual tasks use + beside Specs/ToDo. Team history
keeps version numbers, while ordinary controls use Board team / Use saved team.
[UI references](UI_DASHBOARD.md#kanban-references-r080a) inform this interaction.

## D027 — Supervised asynchronous execution and LiveView components

2026-10-15, R012, accepted before implementation. Setup/planning and battle
coordinators claim durable work and dispatch it to monitored `Task.Supervisor`
children. Long provider/native receive loops run in those task processes, leaving
coordinator and LiveView mailboxes responsive. Retain one setup command and one
battle stage at a time; asynchronous execution alone does not enable parallelism.

Each coordinator and its task supervisor form a `one_for_all` supervision group.
Restarting either stops the old workers before recovery can admit work. Worker
failure is isolated from its coordinator; record interrupted claims without
replay, model output or assumed native cleanup. SQLite remains authoritative.
Login progress returns by message to the current dispatcher, which alone writes
its protected transient ETS table after checking the exact live claim.

Application screens remain authenticated LiveViews with HEEx function components
and stateful LiveComponents where form state requires them. Use the shared
`CuckodingWeb, :live_component` entry point and retain explicit component event
session guards. Keep authentication, redirects, downloads and shell protocol at
their existing controller boundaries. Native process enforcement stays in Rust;
BEAM tasks coordinate it without widening any grant or replacing it with raw spawn.

## D028 — Commit worker completion before notifying its coordinator

2026-10-15, R060f, accepted before implementation. Owned setup/battle workers call
the existing claim-bound domain settlement API after bounded execution and before
notifying their coordinator. The SQLite transaction owns completion, projections
and events; a mailbox message never owns the only copy of a finished receipt.
Coordinators continue to claim/monitor and admit the next stage only after their
current worker ends. Notifications do not settle the result a second time.

If a coordinator restarts after commit, setup keeps its terminal receipt and a
settled battle checkpoint uses the existing explicit Paused/Resume recovery.
If execution or commit did not finish, retain interruption/unknown cleanup without
replay. Cancellation and expiry still use the same domain validation. Invalid or
foreign stage results cannot establish cleanup merely by reporting a boolean.
Unexpected execution/settlement exceptions exit the worker with a fixed shutdown
reason so Task's crash reporter cannot print private provider/database payloads.
The coordinator monitor records the existing interrupted/unknown-cleanup outcome;
committed facts remain unchanged. Valid finished-stage Stop races retain their
cleanup proof only after full binding/result validation.
No native grant, schema, budget, automatic retry or parallel capacity is added.

## D040 — Explicit paired role workers

2026-10-21, R070e. The two-task wave needs optional additional exact bindings to
run simultaneous turns of the same responsibility. Reuse named connections and
Team's immutable revision/command; each required role may explicitly select one
additional agent/model, with inherited name/instructions and independent provider
sessions/worktrees. Do not copy credentials or infer another account/model.

New Starts freeze `role_slots: assigned-pairs-v1` and the resolved additional
bindings. Wave slots 0/1 select primary/additional deterministically; missing
additional binding means the saved shared primary, not dynamic load balancing.
A present invalid/unavailable additional binding blocks Start; it never falls
back. Retries keep the frozen slot, all budgets and the original deadline.
Final stages/configured command checks use the primary responsibility binding.
Keep the two-worker global cap and one turn per exact connection. Older Starts
and planning use their existing bindings. Save launches nothing; explicit scoped
adoption/Start retains authority. Disconnect unassigns the exact connection in
both positions without rewriting history or promoting an extra worker.

This adds no provider grant, tool, port/process reconciliation or real-account
acceptance. Additional providers/custom stages and release gates remain open.

## D041 — Retained preparation checkpoint

2026-10-21, R060m. A native writer worktree may finish before its public result
reaches SQLite. Add a fixed read of the original UUID-derived preparation receipt
and battle tag, bound to the exact saved two-field request and current battle/ref/
source identity. Reuse the existing descriptor-pinned detached/locked/index/raw-byte
inspector; refuse partial/missing evidence rather than rebuilding it.

New Starts freeze `worktree_recovery: retained-preparation-v1`. Only one unfinished
prepare claim with every other attempt settled may use supervised exclusive
inspection. Keep the original Interrupted attempt and append a separate observation.
Verified in-budget, unfenced evidence supplies a Paused checkpoint; Resume stays
explicit and revalidates frozen bindings/worktree integrity. Already-stopping or
fenced claims cannot arm inspection. Expiry or a timing fence racing a completed
read permits verified closure/confirmed Stop only. No native mutation, provider replay,
new authority for older snapshots, or inference from missing processes/receipts.

Multiple unfinished native claims, admission/capture/check recovery, escaped
sessions and actual sleep/provider acceptance remain separate beta gates.

## D042 — Atomic retained preparation wave

2026-10-21, R060n. Two bounded independent writers may both finish preparation
before their replies reach SQLite. New Starts freeze
`worktree_wave_recovery: retained-preparation-wave-v1`. Only two exact interrupted
prepare claims, with all other history settled, may queue R060m's fixed read.
Read one at a time in the exclusive supervised recovery path; retain ordered
membership and separate dated observations, never rewrite or replay attempts.

Advance neither task until both receipts verify within both original stage and
battle deadlines. Commit both next stages and one Paused checkpoint atomically;
Resume remains explicit with original bindings/slots/budgets. A failed read,
expiry or timing fence cannot partially advance the wave. Exact verified closure
is retained for Stop; unknown members still block cleanup. Older snapshots keep
R060m's one-claim limit. This adds no other native/session or physical sleep recovery.

## D043 — Immutable Tabula workflow revisions

2026-10-22, R040o. Introduce a per-board immutable workflow ledger before adding
custom role execution. The original Tabula definition remains untouched revision
zero; later definitions append audited scoped revisions. This additive migration
must preserve prior facts and verified backups; older bundles refuse the new schema.

The first editor changes only bounded unique labels for the existing five semantic
keys/roles in their required order. Scope, expected revision and stable command
key bind Save; active board planning/battles refuse changes. New Starts freeze
the selected revision and complete definition; historical snapshots never change.
Keep the editor/history in Advanced, preserve dirty text and guard its own session.
Actual ordered custom stages and grants follow this foundation; unavailable steps
are not offered as inert columns and do not silently disable the working Start.

## D044 — Explicit custom read stages before implementation

2026-10-22, R050g. A board may explicitly select up to four distinct custom roles
from its own saved team and order their read-only stages between Speculator and
Implementor. New Starts freeze workflow revision/definition, the selected bindings
and `read-role-stages-v1`. Unused roles stay planning-only. The existing host
read grant, per-connection capacity, finite budgets and independent Secutor review
remain mandatory. A report cannot edit criteria or mark a task complete.

Keep core semantic order and historical snapshots unchanged. Configuring names,
order or selected roles appends one scoped revision and refuses active work.
Custom writing stages require a separate effect-aggregation/review contract;
D045 supplies it for explicit newer workflows, preserving this read-only policy.

## D045 — Explicit custom writer checkpoints

Accepted 2026-10-23 for R050h.

Version-four board workflows may place up to four distinct custom team roles before
or after Implementor, after Speculator and before mandatory task review. Each stage
declares read or write. Start freezes `write-role-stages-v1`; old policies never
acquire write permission. Core roles/order remain mandatory.

Every writer uses the existing bounded host task tools and original owned worktree.
A native capture follows each writer. Captures use cumulative final path/hash pairs
from completed, bound, cleanup-verified writer attempts for the exact preparation;
later verified edits supersede earlier hashes for the same path. The next provider
turn verifies the latest retained candidate. Native capture also rejects unreported
bytes, unsafe paths and excess files. Intermediate candidates retain evidence only.
The final candidate still needs independent Secutor/check evidence and serialized
integration. No new native operation, provider tool, shell or network grant exists.
The seventeenth migration indexes exact writer evidence and makes older bundles
refuse startup before dispatch. Back up first; never run an older policy interpreter
on a version-four workflow.

Writer retry abandons the old edits and restarts preparation/Speculator with existing
budgets, exact binding/slot and deadline. Pause/Stop/expiry retain every checkpoint
and edit receipt. Uncertain or interrupted capture is not completion or recovery
authority. UI choices stay in Advanced with guarded immutable workflow saves.

## D046 — Recover complete retained candidate checkpoints

2026-10-23, R060o. New Starts freeze `retained-candidate-wave-v1`.
Only exact restart-interrupted captures with complete private intent, publication,
receipt, app ref, original preparation/battle tag and unchanged owned bytes can
be reconciled. The fixed read verifies the original capture's exact cumulative
file request and current source/battle identity; it writes no Git/file evidence.
A missing receipt is never reconstructed and capture is never replayed.

One or two captures, or a capture/preparation pair, queue exclusive supervised
reads. Each observation is retained separately from the immutable Interrupted
attempt. All members must verify within the original deadlines before next-stage
projections and one Paused checkpoint commit atomically. Resume is explicit and
revalidates existing bindings/ownership. A late/timing-fenced complete observation
can close Stop only; partial/foreign/missing proof cannot advance any lane.
Pure preparation recovery and old policy limits retain their existing contracts.
The new read has a fixed 60-second native / 65-second host budget; it grants no
extra task time, provider turn, native mutation or inference authority.

## D047 — Bind local packages to an explicit build identity

2026-10-23, R100b. A local preview build creates one small public manifest, shared
by the compiled native shell and packaged Phoenix release. It records a build
UUID/date, source revision/dirty observation, digest of enumerated application
inputs, target, schema and actual tool versions. Input enumeration excludes
generated/private storage and unrelated files; links/special files and drift
during the build refuse packaging evidence. The digest is application-input
identity, not proof of dependencies, signature provenance or reproducibility.

The shell checks the release manifest before data preparation and passes only
its expected public build UUID and manifest digest. Production configuration
verifies its own compiled copy before migrations/dispatch; authenticated Settings reads the validated public
projection. Source development ignores packaged metadata and identifies itself
explicitly. No manifest grants provider access or workflow authority.

After strict/deep seal verification, retain an exclusive private receipt with
the actual helper and resource-manifest hashes. Never overwrite an older build
receipt, expose absolute paths/credentials or label an ad-hoc preview notarized.
Developer ID, clean-machine, update/rollback and real-provider evidence remain
required separately.

## D048 — Inspect mixed interrupted claims for Stop only

2026-10-23, R060p. New Starts freeze `mixed_closure: retained-mixed-closure-v1`.
A restart with exactly one interrupted provider claim and one interrupted native
capture/preparation in different task lanes may retain a Stop-only inspection
queue. Inspect the provider first using R060l, then the exact native operation
using R060m/R060o's fixed read. Both original claims, worktrees and edits remain
immutable; observations are separate and dated. No provider output is recovered,
no checkpoint/card/head advances and Resume/Retry/Skip remain unavailable.

Only verified closure of every original claim permits confirmed Stop. A failed
read does not prevent reading the sibling's exact proof, but never proves the
failed claim closed. Expiry/timing races cannot turn these observations into
continuation authority. Keep the queue durable across coordinator restart and
exclusive with ordinary dispatch. Historical snapshots, preexisting Stop/fences,
other native stages and missing receipts gain no authority. No new native tool,
provider capability, inference, schema change or process-absence inference.

## D049 — Separate typed provider failures from retry authority

2026-10-23, R060q. Parse only scoped Codex protocol error discriminants, never
message text. Retain usage_limit, provider_overloaded and rate_limited as public
codes; unauthorized remains not_connected. Unknown/malformed variants retain the
generic failure. An exact error notification with willRetry true remains inside
the original bounded provider turn; no new host claim/session/budget is created.

New Starts freeze automatic-provider-backoff-v2. Only explicit provider_overloaded
adds automatic waits, using 5–7 then 20–22 seconds with stable per-attempt jitter,
inside the existing two-retry lifetime cap and original deadlines. Historical v1
waits/reasons keep exact behavior. HTTP 429 alone is ambiguous and exposes manual
Retry only; usage exhaustion is not retryable. The protocol carries no trusted
Retry-After delay, so none is inferred. Cleanup uncertainty, native failures,
review verdicts, binding drift and sibling drains retain every existing gate.
Cursor/other adapters and real-provider rate-limit acceptance remain required.

## D050 — Verify exact Codex cohorts and bind isolation versions

2026-10-23, R020s. An updated installed Codex remains unsupported until its exact
version passes fresh-profile non-inference configuration/thread/isolation and
single-process conformance. Keep setup-only baselines separate from execution
cohorts. No semver range, guessed compatibility, default model/account or widened
permission policy may replace those checks. Real-provider acceptance stays open.

When a cohort is admitted, freeze the selected connection's actual observed
version in isolation requests. Native canaries report their actual verified
version; host settlement must match that exact request as well as executable and
version-command identity. A receipt for another supported cohort cannot publish
success. Preserve immutable historical commands/receipts and existing grants.

## D051 — Claude subscription sign-in after approval

2026-10-23, user decision, R090a. Use subscription sign-in after Anthropic approval.
Approval is unconfirmed. Keep Claude unavailable until approval and the existing
adapter conformance gates; never borrow personal tokens or silently switch billing.
[Authentication boundary](AGENT_RUNTIME_ADAPTERS.md#provider-evidence-checklist).

## D052 — Verified task-local attention may permit independent work

2026-10-23, R060r. New Starts freeze `blocker_scope: task-local-continuation-v1`.
Only exact validated provider `blocked` receipts or exhausted task Secutor review,
with verified cleanup, are task-local. Drain all current workers before continuing
independent ready tasks. Preserve blocked tasks, pending dependents, failed edits,
criteria, binding slots, consumed limits and the original deadline. No automatic
Skip, lost-work acceptance or final completion with unresolved tasks.

Other failures retain Arena-wide admission closure and existing backoff/recovery.
User Pause prevents automatic continuation; restart still needs explicit Resume.
Controls remain separate and revision-guarded. Prioritize shared/uncertain attention.
The eighteenth forward-only migration requires a backup and prevents older bundles from
interpreting running battles with unresolved lanes; a DB trigger refuses claims
on blocked tasks under the new policy. Historical snapshots keep their behavior.

## D053 — Verify a private database copy before startup migration

2026-10-23, R100c. With the existing exclusive workspace launcher, create a fresh
UUID backup before changing an existing known schema. Use SQLite's consistent
copy operation, readonly integrity/FK/schema verification, bounded hashing and
file/directory synchronization. Publish a private immutable receipt only after
verification; any failure stops startup before migration/authentication/dispatch.
Retain partial attempts and never reuse them as proof. Fresh/current schemas do
not need a new copy; future/unknown schemas still refuse.

Settings may read dated whitelisted metadata through a fixed private pointer;
it is an observation, not a new integrity claim or restore action. The database
copy excludes provider profiles, project folders and retained native artifacts.
It never authorizes overwriting later work, auto-downgrading or replacing an app
while native effects are uncertain. Full update/restore and physical power-loss
acceptance remain release gates. No schema or provider-grant change.
