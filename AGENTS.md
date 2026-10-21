@/Users/mpak/.codex/RTK.md

# Cuckoding contributor rules

These rules apply repository-wide. More specific rules may strengthen safety,
auditability and verification, not weaken them. The 2026-10-06 user reset replaces
the previous product direction. The implemented boundary includes named
Codex/Cursor setup, draft planning, owned worktrees and the first bounded
sequential Codex/Cursor Arena loop. [Architecture](docs/ARCHITECTURE.md) names source
owners; [Plan](docs/PLAN.md) owns remaining acceptance. General toolchain checks,
full recovery, same-board parallel workers, remaining providers and real-account battle
acceptance remain open.

R070a freezes `scheduler: isolated-arenas-v1` in new Starts. SQLite admission
limits battle stages to two globally, one per battle/Arena and one provider turn
per exact connection. Unverified provider cleanup reserves that connection even
after a failed/interrupted attempt; missing processes never prove release.
Capacity waits consume no turns/retries. BattleRunner fairly rotates ready Arenas
with monitored Task.Supervisor workers; legacy Starts and retained integration
inspection stay exclusive. Keep one_for_all clock/tasks/coordinator restart and
per-Arena Stop/Pause isolation. This does not enable same-board task cloning,
combined-candidate integration, new tools or real-provider concurrency acceptance.

R060a Pause closes stage admission and lets the current bounded stage finish.
Show Paused only at a durable boundary with verified worker cleanup; retain its
receipt and next stage without replay. Pause/Resume use persisted control revisions
and session/form guards. Paused/pausing battles retain Arena exclusion and draft
locks. Resume preserves frozen scope, consumed turns/review rounds and the original
wall deadline; revalidate exact connection bindings and native ownership before
subsequent effects. Clean paused boundaries survive restart; interrupted pausing
workers remain needs-attention. Stop still cancels. Do not present this as full
crash/sleep recovery or native session continuation.

R060b freezes `provider-retry-v1` with two explicit provider retries per task and
two shared by final stages. Only settled transient role failures with retained
normalized receipts and verified cleanup qualify. Keep fresh attempt/session IDs,
all failed edit evidence, exact bindings, consumed budgets and deadlines. Failed
Implementors restart through a new worktree/coordinator/Speculator on the reviewed
head. Do not replay native stages, bypass rejected/blocked review, retry policy
drift or uncertain effects, or give historical snapshots implicit retry authority.
Retried failures remain immutable and count toward lifetime limits; Pause/Resume
may recognize them as settled only through the recorded retry transition.

R060j freezes `provider_backoff: automatic-provider-backoff-v1` in new Starts.
Only R060b-eligible settled `connection_lost`, `profile_busy`, `timeout` and
`launch_failed` role failures with verified cleanup schedule SQLite waits of
5/20 seconds inside the same two-retry task/shared-final budget. No sleeping
worker owns the wait. At due admission recheck exact attempt/bindings, original
deadline and consumed limits transactionally before a fresh claim; writer retries
retain the fresh worktree/coordinator/Speculator path. Generic provider/turn errors
remain manual. Cancel, Stop, Skip and timing fences cancel the wait; startup
requires explicit Retry. Preserve historical manual-only snapshots, failed
receipts/edits, session/form/revision gates and all R060b exclusions. This does
not recover interrupted native sessions or prove real-account acceptance.

R060c freezes `task_selection: skip-task-v1` in new Starts. Skip confirms the exact
current task/control revision at a clean paused boundary or settled task-local
provider block/transient failure/review exhaustion. Verify cleanup, bindings and
remaining limits; never skip active workers, native/policy failures or final review.
Atomically mark the task skipped and transitive dependents deferred; retain every
draft, frozen snapshot, attempt and abandoned edit. Continue independent work from
the reviewed head; paused battles stay paused. Bind final criteria to the retained
subset plus explicit omissions, keep configured checks and independent review, and
finish as Partial, never Completed. If everything is omitted before any task
completed, stop without inference. Only recorded skipped failures become settled
for later controls; no replay or cleanup uncertainty bypass.

R060d recovers running/pausing battles to Paused only when every attempt is
settled with verified cleanup. Increment the control revision and record
`battle.recovery_paused` with the saved stage/task; preserve all authority,
attempts, budgets and result context. Existing clean pauses remain unchanged.
Resume is explicit and retains binding, deadline and native integrity checks.
Never infer cleanup from a missing process or replay an unfinished claim; those
still need inspection. This is checkpoint recovery, not sleep/lease reconciliation.

R060e retains exact, bounded late stage receipts as immutable `expired` attempts
and records `battle.stage_expired` plus attention atomically. The executor's
deadline cancellation may be retained only as rejected evidence. Never advance
tasks, reviewed heads or budgets, or enable Resume/Retry/Skip from these receipts.
Confirmed Stop can close the battle only when every attempt verifies cleanup;
historical missing receipts and uncertain native effects remain blocked. No
receipt replay, artifact deletion, deadline extension or process inference.

R060f commits setup/battle outcomes through their existing domain transactions
inside the owned supervised worker, before notifying its coordinator. Completion
messages only release admission; they never settle a result twice. Preserve
terminal facts on subsequent worker/coordinator failure. A committed battle
checkpoint still restarts Paused with explicit Resume; missing receipts retain
inspection gates. Sanitize unexpected worker exits before OTP logging. Invalid/
foreign results cannot establish cleanup; a Stop racing a valid finished stage
may use only the exact bound, fully validated cleanup receipt, without accepting work.

R060g freezes `native_recovery: retained-integration-v1` in new Starts. A restart
may reconcile only an interrupted integration with complete retained native
intent/publication/receipt and verified source/ref/candidate/worktree identity.
Use the fixed read-only operation under the repository lock in a supervised
worker. Never recreate a receipt, replay integration or rewrite the interrupted
attempt. Append the observation and next checkpoint atomically; pause for explicit
Resume with original bindings, budgets and deadlines. Late verified effects allow
Stop cleanup only, never advancement. Historical grants, interrupted Stop, failed
inspection, absent receipts, provider sessions and sleep gaps remain blocked.

R060h freezes `timing_guard: elapsed-gap-v1` in new Starts. Keep BattleClock in
the battle one_for_all group, independent of the coordinator; guard loss must
stop old workers before its baseline resets. Check before admission, during
helper polling and before settlement. Persist UTC/monotonic gap observations
before closing admission; never call them proof of sleep or cleanup. Clean
boundaries pause for explicit Resume; backward time or active work blocks
continuation. Cancel active helpers through existing ownership protocols and
retain the bound rejected receipt without advancing cards/head. Active fenced
work permits Stop only after recorded verified closure; never Resume/Retry/Skip
it or bypass the fence through native integration recovery. No deadline extension.
Physical sleep, lease/process reconciliation and active-time
accounting remain open.

R060i freezes `idle_sleep: shell-lease-v1` in new Starts. Phoenix derives a
boolean lease request from durable work state and original deadlines. Ordinary
Pausing protects only its current bounded attempt; Stop/timing cancellation has
at most five seconds of eligibility for cleanup. The authenticated five-second
shell heartbeat requests one fixed 15-second PreventUserIdleSystemSleep assertion.
Use explicit OS timeout TurnOff, retain the owned ID until release and release
on idle/pause/quit/error/drop; never use timeout Release with a reusable ID.
Assertion API failures remain nonfatal. Record only authenticated normalized
held/released/unavailable transitions; Settings ages reports using UTC and
monotonic time, distrusts backward time and shows the last report and age,
never guaranteed current protection. Historical snapshots gain no policy.
This cannot prevent lid/forced sleep, keep the display on, extend deadlines or
prove cleanup/recovery. Source UI development does not own a native assertion.

Preserve these implemented contracts:

- Supported versions, observed authorization, catalog freshness, model entitlement
  and execution grants are separate. Never substitute bindings silently.
- Agents are named connections, not a singleton provider choice. Additional UUID
  records and private `agents/<UUID>` profiles remain independent. Legacy `codex`
  retains Workspace projections and `agents/codex`; do not rewrite its historical
  commands or team bindings. Scope setup receipts, model selections and planning
  to the exact connection ID, with no account/runtime/model fallback. Cursor setup
  uses only fixed version/status/models/login/logout commands, file credentials,
  empty inherited environment, disabled provider debug logging and transient provider-scoped login URLs. Cursor
  initial planning remains unsupported; task execution uses the R020p grant below.
- R080b roster Disconnect uses verified native logout when available. If the
  executable is missing/changed/unverified, `local-disconnect-v1` disables only
  that saved connection and unassigns current default/Arena/board roles in one
  audited command transaction. Keep provider authorization Unknown and explicitly
  report that provider sign-out was not attempted; retain the private profile.
  Never run the changed executable, silently select another account, erase
  credentials or alter historical/frozen bindings. Preserve battle, setup-busy,
  session/form/revision gates and stable receipt replay, even after re-verification.
- R080e projects verified native logout as Disconnected while preserving its raw
  checked/not_connected audit receipt. Recognize older successful receipts only
  through the exact current completed logout command, provider kind and connection
  ID; inspection, failure/cancellation and uncertain cleanup are not logout proof.
  Reconnect opens authorization even if old saved model choices remain.
  `bin/reset-agents` is an offline full-workspace reset, not a provider logout or
  project-folder deletion. Require recognized private canonical storage, the
  unchanged exclusive shell lock, settled work, SQLite integrity/FKs and explicit
  confirmation. Retain all previous contents in a private sibling archive with
  a dated reset receipt; move the marker first so interrupted moves block startup.
  Never follow profile links, purge archives, remove project Git metadata or run
  a real user's reset merely to test the helper.
- R080f keeps Team repair navigation bound to validated Arena/Tabula IDs. Save
  leads back to that board's team review; navigation never adopts a team.
  Use saved team is an explicit confirmation submit bound to its component form
  key and displayed current/default revisions. Rotate the key on revision changes;
  retain session, domain confirmation and active-planning gates. Compare role
  definitions for change notices, without rewriting immutable revision history.
- Team revisions and scoped adoptions are immutable. Arena adoption affects new
  boards; Tabula adoption affects future planning only and waits for active
  planning. Guard both displayed scope/default revisions and retain old receipts.
- Registration reads directory metadata only. Git inspection, initialization and
  initial commit require their separate recorded intent/consent. Revalidate folder
  identity; preserve Git locks, exact byte/hash consent and uncertain partial effects.
- Drafts are scoped and revision-guarded; only Specs/ToDo are writable. ToDo is
  draft readiness, not independent review or delivery authorization.
- Draft prerequisites live in immutable revision content, projected from the
  current revision. Validate same-board references and cycles in the save
  transaction. Old history means no prerequisites; legacy saves omitting the
  field preserve existing links. Future deletion/scope changes must preserve
  graph integrity. Planning links never authorize execution.
- R040f document preview reads only explicit bounded `.md`/`.txt` selections with
  pinned native descriptors. Persist exact text/hash snapshots locally before
  provider consent. Freeze the scoped preview in the planning request; reject
  expired/foreign snapshots. Never grant the provider Arena file access or treat
  document text as policy. See [Security](docs/SECURITY.md) and [Data](docs/DB.md).
- R040l adds the explicit `folder-documents-v1` local read: docs-first eligible
  text/source snapshots, 2,000 entries, six directory levels, 16 files, 16 KiB each
  and 64 KiB total. Preserve pinned descriptors, exclusions, skip/limit counts and
  exact untruncated snapshots. Empty folders need a brief; sending snapshots still
  requires separate provider consent. No Git prerequisite or live Arena grant.
- Planning uses the assigned Speculator and fresh connection/model snapshot,
  stdin text and the existing no-tools empty-scratch grant. Import validated
  proposals into Specs once with source-command/index provenance. Cancellation
  and expired claims cannot replay usage or accept late text/results.
- New planning uses `brief-plan-v3` with up to 16 source snapshots: distinct prerequisite indices refer only to
  earlier suggestions; citation indices refer only to snapshots frozen in that
  request. Reject downgrade/malformed references before storage. Resolve imports
  through same-board receipts and preserve earlier user edits. Keep v1/v2 receipts
  readable with their original bounds; never infer missing links. A scoped citation is not proof of its truth.
- R040m freezes `card_creation: automatic-v1` in new planning consent. Commit the
  validated completion, all Specs cards, resolved prerequisites and existing
  proposal/index receipts/events in one immediate transaction. Reject expired or
  lost claims before writes; never replay inference or import on page load.
  Requests without this field retain explicit manual imports, including partial
  imports and later edits. Reanalysis appends a new graph; it never replaces tasks.
- Accepted specifications freeze a saved draft, prerequisite revisions and original
  citations in `accept_spec` before writing private Markdown. Verify bytes/hash and
  current revisions before acceptance/ToDo/history/event commit together. Never
  overwrite or replay uncertain artifacts. Later task/prerequisite edits invalidate
  current acceptance; downloads require a live session and matching file hash.
  Specification acceptance never authorizes execution or modifies Arena files.
- Project checks are explicit user-authored Arena revisions. Preview exact literal
  argv, relative directory and timeout; require fresh consent for changes/removals.
  Save revision/command/event atomically and reject stale or recovered foreign forms.
  Never infer execution permission from these declarations or consume proposed
  commands as policy. Future battle admission must freeze a revision and validate
  executable identity, owned paths and actual grants before running anything.
- Stateful LiveComponents install the shared session event guard and receive the
  server-owned session ID explicitly; parent hooks do not authorize their events.
  Preserve unsaved text and clear stale consent during live updates.
- Battle preview is a read-only observation, not a frozen battle, grant or Start
  authorization. Use the Tabula's assigned team and current revision's acceptance
  receipt; verify retained Markdown and prerequisite revisions. Mark old previews
  stale on updates/expiry. A recorded HEAD or model diagnostic never proves live
  Git cleanliness, worktree permission or task completion. Future Start still
  needs atomic authority and fresh admission; optional spec acceptance must not
  introduce ordinary per-task approval after Start.

- Worktree preparation freezes a fresh committed Git observation and source folder
  identity before native effects. Derive private destinations from command UUIDs;
  exclusively create ownership records outside detached locked checkouts. Reject
  unsafe filters/tree layouts and preserve original index/working files. Retain
  all partial effects; expired/cancelled claims cannot publish success or replay.
  Creation receipts never grant execution or prove current checkout integrity.
  Keep this setup utility separate from read-only Battle preview; future Start
  still owns ordinary worktree admission under its single bounded authorization.

- Worktree inspection binds a completed preparation and revalidates ownership,
  directory identity, detached locked registration, index entries and raw tracked
  bytes. Extra files are flagged without reading their contents. Do not trust Git
  index flags as cleanliness proof. Built-in checkout transformations can report
  differences. Keep observations dated, retain uncertain state, reject late/foreign
  receipts and never use inspection as a grant or future-integrity guarantee.

R020n task turns use only `host-task-tools-v1` dynamic list/read/edit tools.
Keep native root identity and policy-path checks, finite call/byte limits,
compare-before-write, fsynced effect receipts, cancellation and no replay.
Runtime shell/file/network tools remain disabled. R020o enables only the pure
Code Mode interpreter/router for task turns; diagnostics/planning keep it off.
State the host-service read/write grant separately from runtime scratch access;
never widen filesystem permissions to fix a model misunderstanding. Read-only
roles cannot edit. A transport
report never grants battle authority or marks a card Completed; R050 must own
that binding. Do not add a new mandatory setup diagnostic. R020o has one
consented GPT-6.1 Sol synthetic read/edit success with verified final bytes and
normal child cleanup. This is not real Arena, independent review, crash/sleep
or cross-provider acceptance; preserve those remaining gates.

R020p adds Cursor `2026.09.15-d2fe57e` task execution through ACP in an empty
private workspace. Use the exact CLI catalog alias; verify Cursor's generated
base model and every parameter against ACP, without guessing alias syntax or
accepting a default. Keep public requested alias, runtime model and parameters
separate. The generated schema-valid configuration must retain deny rules for
native read/write/shell/MCP/web tools, ask mode and restricted sandbox settings
before every prompt. Reject native callbacks, tool activity and model/config drift.
Only validated JSON proposals reach the existing host list/read/edit service.
Retain effect receipts; remove private runtime session stores after owned cleanup.
Never persist provider thought frames in Cuckoding receipts or UI. Hard-kill
cleanup of interrupted provider session stores remains a recovery gate.
No Cursor fallback to Codex. Command checks still require a Codex Implementor;
Cursor initial task generation and general shell/toolchain execution remain open.
Use synthetic provider acceptance separately from fixture or full Arena evidence.

R050d1 host candidate capture accepts only bounded task-tool path/hash pairs in a
verified owned checkout. Preserve the original source and task HEAD/index, verify
all other tracked bytes and modes, reject extras/protected paths, and retain
exclusive intent/index/publication/receipt artifacts and UUID-derived app refs.
Never replay uncertain capture. A dated candidate verification is neither a grant
nor independent review; future integration must bind exact criteria/check evidence.

## R050e / R050f execution boundary

The sequential Codex/Cursor Arena loop is implemented in `Battles`,
`BattleRunner`, `BattleExecutor` and native battle Git/check helpers. Start freezes
membership/criteria/team/check revisions and finite limits; admission binds the
current committed source and exact executables. Battle/task snapshots and attempt
requests are immutable. Frozen drafts cannot be edited; new unrelated drafts wait
for a future battle. Provider text cannot grant authority or accept failed checks.
Keep Secutor sessions independent, bind review/checks to the candidate, and CAS
only `refs/heads/ccoding/battles/<UUID>`. Preserve the source checkout and every
uncertain effect. Failed checks return through Secutor/Speculator within the same
review budget; final rejection needs attention. Stop waits for verified cleanup;
startup interrupts unfinished claims without replay. Full recovery remains R060.

R050f makes task criteria the ordinary verification contract. Speculator includes
expected outcomes and verification instructions in each generated task's existing
`criteria` field. No mandatory separate Arena command-check configuration. New
`arena-loop-v2` snapshots with an empty command scope skip command stages, retain
independent task/final Secutor reviews and never emit passing command receipts. A completed
review also requires a successful host file-inspection tool receipt; a report
with no inspection cannot pass.
Only that exact version/empty scope has this exemption; historical snapshots and
configured commands retain their gates. Missing required runtime evidence must
block review, not be inferred from code. Generated task text is never executable
policy. Keep optional command declarations in Advanced; retain existing revisions,
consent, limits and failures. Never rewrite saved cards to invent verification.

The initial check grant `codex-check-single-process-v1` is deliberately limited:
frozen native system executable/argv, empty profile, network denied, private
verification checkout, protected paths, hard no-fork limit and owned session
identity. Do not advertise Mix/npm or other subprocess toolchain support. Retain
partial check evidence and cleanup uncertainty, including on cancellation. Never
infer real-account battle acceptance from fixtures or synthetic prior task turns.
See [Arena loop](docs/ARENA_LOOP.md) and [Plan](docs/PLAN.md).

## Mission and product contract

R020m's optional `codex-isolation-v1` diagnostic runs fixed commands against two
disposable fixtures with a fresh empty profile, never an Arena or signed-in profile.
Bind its receipt to the exact connection/version/executable observation. Preserve
explicit temporary-root denial, bounded output/deadline and owned group cleanup;
expired/cancelled work cannot publish success or replay. A dated CLI sandbox pass
does not verify model tools or authorize repository execution. Keep it optional
and outside the four required setup steps.

Build a local-first macOS menubar application opening a minimal Phoenix LiveView
UI in the default browser. Setup should take ten minutes with stated runtime/
account prerequisites. Users save agents/models and roles once. The 2026-10-10
Arena clarification makes the normal project flow **Add folder → Create tasks →
Start**. It supersedes a mandatory Tabula/Describe/setup wizard sequence.

Adding a folder uses the saved team and creates the default Tabula automatically.
Create tasks asks Speculator to analyze `docs/` and relevant eligible project files
with an optional brief, then creates validated cards without per-card imports.
Start is one execution button on that same board. Summa Rudis coordinates agents
and automatic card movement; Secutor independently judges completion and sends
review findings through Speculator. Keep custom boards/roles, check declarations,
Git/worktree details, revisions and logs in contextual Advanced/Inspect controls.
Do not require these as routine setup screens or repeat approvals per task.

R002 implements atomic default-board creation, immediate Arena navigation and
Advanced disclosures. R040l adds bounded folder snapshots and consented Speculator
analysis; R040m creates the validated cards automatically. R050e adds the first
bounded sequential Codex/Cursor battle; general toolchain checks and real-account battle
acceptance remain open.
Preserve scoped reads/consents. Folder analysis needs a bounded read grant;
Start owns a separate bounded execution grant.
Ask before Git initialization or initial-commit mutations, only when needed;
no Git setup is required just to analyze docs. Do not substitute a preview for a
working Start button. [Plan](docs/PLAN.md#next-delivery-order--simple-arena) gives
the immediate delivery order; [D022](docs/DECISIONS.md#d022--simple-arena) records
the boundary change.

Arena simplification must preserve the separate `/agents` roster/add wizard and
`/team` role/agent/model editor. Do not replace them with discovery-only setup.
When controls seem missing, verify the running bundle and data root first:
obsolete `CCoding.app` is not the current `Cuckoding.app`. Preserve saved test
workspace launchers and their data selection when rebuilding; a source change
or successful smoke test does not update an already-running app.

**Speculator** writes specs/tasks; **Implementor** implements; **Secutor** judges
completion; **Summa Rudis** coordinates the process. Parallel role instances use
separate worktrees/sessions. Review comments return to Speculator. Phoenix
validates every agent proposal; model text never grants authority or marks work
complete. The global and Arena **Tabula Gladiatorum** expose activity and controls.

Read before implementation:
[Product](docs/PRODUCT.md), [Architecture](docs/ARCHITECTURE.md),
[Data](docs/DB.md), [Flow](docs/FLOW.md), [Security](docs/SECURITY.md),
[Execution](docs/EXECUTION_ENVIRONMENTS.md), the claimed task, Ponytail full and
the relevant local skills. [Plan](docs/PLAN.md) is the ordered acceptance checklist.
Do not restore the old implementation or treat historical tests as current proof.

## Non-negotiable boundaries

- SQLite is the durable source of truth. Never make a process, LiveView, terminal
  buffer or agent session the sole owner of workflow state.
- Bind loopback only. Require one-time shell bootstrap and a short-lived browser
  session with host/origin/CSRF protection.
- Agents and commands run as supervised host children with owned process groups,
  worktrees and approved paths. The host runner is not a sandbox.
- Never give agents GitHub/application/provider credential values through app
  prompts, config, argv, environment or MCP. Provider runtimes manage their own
  scoped authorization; Cuckoding stores references/status, not token contents.
- Never expose the real home, SSH/cloud credentials, personal Keychain or unrelated
  repositories through app configuration or grants. Record actual runtime
  enforcement and unsupported restrictions honestly.
- No role, repository document, skill or provider output may expand permissions,
  directly mutate the DB or execute changed policy. Agents may propose changes
  to protected configuration, including `.cuckoding/`; activation requires an
  explicit human decision and audit event.
- Start battle records explicit bounded local-completion authority. Independent
  Secutor review and retained evidence are required; Summa Rudis cannot override
  a failed review. Push, PR, user-branch merge and release remain separate human
  actions through host-side services if implemented.
- Do not display/persist hidden chain-of-thought. Keep public summaries, tool
  activity, artifacts, decisions and normalized transitions.
- Project knowledge stays project-scoped; any later global publication requires
  human approval. Deferred subsystems are not implied by available skills.
- One provider/plugin/network failure or sleep/wake must not make the whole app
  unusable. Preserve old user databases, profiles, branches and logs through the
  source reset; use a separate rebuild data root until migration is verified.

## Engineering

- Prefix every repository shell command with `rtk`. Use `rtk proxy` for exact
  output or semantic incompatibility and record the reason in the worklog.
  Product command declarations stay unwrapped; policy validates them before RTK.
- Apply Ponytail full to every change/review: understand the complete flow and
  callers, reuse existing code, prefer standard/native facilities, minimize files
  and dependencies. Minimalism never removes validation, durability, security,
  privacy, accessibility, observability or required acceptance.
- Use `rtk rg` and direct source inspection. No XERJ/indexing requirement.
  For unfamiliar work follow [reference coding](docs/REFERENCE_CODING.md), check
  peer licenses and record the source revision and `path:line`.
- Use explicit supervised OTP components and behaviours at implemented replaceable
  boundaries: runner, adapter, secret store, VCS host, metrics collector, plugin
  kinds and knowledge backend. Do not scaffold deferred subsystems.
- R012 runs provider/native I/O in monitored Task.Supervisor workers; keep long
  receive loops out of GenServer/LiveView callbacks. ExecutionSupervisor pairs
  each coordinator with its task supervisor under `one_for_all`, stopping old
  workers before recovery. Persist interrupted claims without replay or inferred
  native cleanup. Login progress must match the current task/live claim, stay in
  protected transient ETS, and be redacted from OTP status/error reports.
- Make commands idempotent with stable keys and expected revisions. Write events
  and state transactionally before broadcast. Reconcile uncertain external
  effects before retry; never claim exactly-once external execution.
- Use worktrees for concurrent isolation, process groups and per-run ports.
  Exclusive resources use TTL/heartbeat leases; reconcile sleep gaps before
  expiring/reassigning live ownership. Persist UTC time and measured monotonic
  durations with explicit sleep gaps.
- Keep provider payloads bounded and redacted only when needed for diagnosis;
  normalize business fields. Never label inferred usage/cost/savings measured.
- Version workflows, role/team bindings, grants, configuration and artifacts.
  Frozen battle snapshots remain immutable; settings updates affect future work.
- Executable discovery reads known locations/metadata only. Manual overrides,
  supported-version probes and app-owned authorization remain distinct. Host
  discovery hints never become child environment or filesystem grants.
  The native fixed `--version` probe uses a private scratch directory, empty
  inherited environment, bounded output and owned group cleanup. Interrupted
  probes and connection inspections require a new consented command; never replay
  them as metadata discovery. The fixed Codex app-server inspection permits only
  initialize/config-read/account-read/model-list, keeps raw frames and account
  identifiers out of Cuckoding storage, and rejects unsafe profiles. Keep the
  explicitly selected executable: desktop and standalone Codex can advertise
  different catalogs. Verified versions are 0.146.0, 0.162.0-alpha.2 and 0.162.0-alpha.17.2. Allow
  `account/updated` during authoritative `account/read` only; unsolicited login
  completion, server requests and later account drift remain refused. Retain the
  last catalog as stale after inspection failure; age it out after 24 hours.
  R080a keeps aged successful catalogs reusable for existing planning/task role
  bindings; the 24-hour limit still gates new model choices and optional diagnostics.
  Failed/invalidated observations and exact account/executable/model drift refuse
  reuse. Native preflight remains mandatory before usage; no silent substitution.
  Confirmed Disconnect unassigns the exact connection in current default/Arena/board
  teams through immutable revisions/adoptions in the accepted logout transaction.
  Preserve historical snapshots, other agents and role instructions. Refuse agents
  used by unfinished battles and busy profile/planning work. Failed logout leaves
  roles unassigned; reconnect never implicitly restores assignments.
  Fetch the full bounded agent catalog, including entries hidden from its default
  picker. Validate/preserve that flag and expose additional models without
  inventing IDs or inferring entitlement; older cached rows remain readable.
  Cursor catalogs permit up to 512 rows within the fixed 64 KiB stdout limit;
  retain every advertised variant. Saved selections permit up to 512 catalog-bound
  IDs. Reject malformed/partial/duplicate/over-limit lists without publishing a
  truncated fresh catalog.
  Login/logout invalidate account/catalog observations before launch and require
  separate consent. Serialize profile operations through the ledger and native
  lock; never replay interrupted authentication. Hold cancellation until helper
  exit/cleanup or report uncertainty. Keep validated login URLs transient and
  behind the session-protected redirect, never in LiveView assigns, SQLite or logs.
  The model diagnostic requires separate usage consent, a fresh identity/catalog
  snapshot, verified restrictive effective config and one fixed prompt. Reject
  model drift, tool activity and foreign completion. Ignore bounded informational
  warning/deprecation notifications without storing their text; requests and account
  drift remain refused. Persist only the public
  receipt; keep requested/runtime model separate. Hold cancellation through
  cleanup and never replay interrupted inference. This grants no repository work.
- Inspect processes by executable, PID/start identity, working directory and
  listeners. Never dump raw argv/environments. Redact before logs/UI/artifacts.
- For a requested restart follow [Development](docs/DEVELOPMENT.md): identify only
  owned instances, shut down gracefully, preserve data, verify cleanup, then
  launch one chosen build. An unusable tray may use the documented normal backend
  shutdown only after verified idle state, backup and native process identity.
  Never kill unrelated provider apps.

## UI

For source UI development use `rtk proxy bin/dev.server` after building the native
helper. Phoenix LiveReload and its iframe CSP exception must remain dev-only.
The launcher retains the normal bootstrap/session/heartbeat with separate
`.ccoding/ui-dev/` data. Keep it loopback-only and do not import real app profiles
for UI tests. Tidewave was removed; do not restore its MCP/toolbar or broad CSP
exceptions without a new user request.
See [Development](docs/DEVELOPMENT.md#ui-development).
If the developer data lock is held, identify the existing owner; never unlink or
steal it. When handing terminal startup back to the user, stop only your verified
preview instance and confirm cleanup rather than leaving a competing launcher.

Use Phoenix LiveView, HEEx and Tailwind. Keep one reusable accessible dialog
convention; validation lives in domain contexts/LiveView and small hooks cover
native browser behavior. No second frontend framework.
Application screens use LiveView and reusable function components; stateful
components use `CuckodingWeb, :live_component` and explicitly install the shared
session event guard. Keep provider work in supervised tasks. Authentication,
redirects, downloads and shell protocol retain their controller boundaries.

Canonical navigation routes are `/agents` for the roster/wizards and `/settings`
for workspace settings. Keep sidebar, cross-links and tray handoffs consistent;
legacy redirects must not bypass browser session checks.

Honor [the UI contract](docs/UI_DASHBOARD.md): slim sidebar, one/two primary
regions, modern mouse-friendly TUI appearance, no decorative dashboard clutter.
Use the shared near-black/electric-green palette (`#050807` / `#82ff52`), restrained
HUD borders and readable system type. Keep cinematic artwork on the public site;
internal forms retain the one/two-region layout and visible keyboard focus.
R080a uses the shared native dialog/hook for Create tasks, Repository setup,
Add another board, task editing and Disconnect confirmation. Preserve open state,
text, Escape/close and focus return. Specs/ToDo expose labelled + controls; other
columns cannot create manually completed work. Show Board team / Use saved team;
version numbers belong in Team history. Closing a dialog does not cancel work.
R080c keeps the five-step Agents → Roles → Arena & Tabula → Create tasks → Start
rail as navigation only. Home projects saved setup; it never adopts a team or
launches usage. Team exposes agent/model choices directly; optional role details
retain dirty text/disclosure state. Board team is a direct dialog with explicit
revision-guarded adoption. Keep Start's bounded scope visible, full limits in
Inspect and blockers grouped by exact connection/status. Never claim the
ten-minute goal is verified from UI/fixture tests.
R080d distinguishes an assigned agent without a model from a missing agent.
Route binding repairs to the affected Team role; provider status repairs still
open the exact connection. Preserve submitted agent/model pairs on Save and
validate them through Team's catalog rules; an editor agent change still clears
the old model. Incomplete teams remain saveable drafts with an explicit Start
warning. Never infer a model, restore disconnected roles or silently adopt a team.
Every long action shows state, elapsed time, role, runtime, model when known,
and pause/resume/retry/stop/inspect as appropriate.

Provide keyboard/menu alternatives to every drag action; enforce the same gates.
Preserve text, focus, scroll and disclosures through live updates. Bind checkbox
state in LiveView; clock/unrelated updates must preserve it. Agents setup follows
Choose Agent → Connect and Authorize → Select models → Save. Explicitly labelled
version/profile action buttons record consent bound to the current form key and
setup revision; do not restore the old checkbox wall. Keep separate usage consent
for optional inference. Fresh connections clear it while preserving model choices.
Reject recovered stale forms and reviewed saves. Store selected catalog IDs plus
resolved models in audited revision-guarded SQLite commands. Filter new Team
choices, never rewrite existing roles or treat selections as entitlement/grants.
Hide sign-in when connected; retain sign-out and refresh.
R020q shows Refresh only while signed in. A sign-in click opens its pending tab
during that user gesture; the small AgentLogin hook follows only the exact login
command's existing session-protected local redirect once ready. Keep the in-place
fallback for blocked/closed tabs and reconnects; never expose raw provider URLs,
replay login or let browser state grant native authority. Prefill editable names
and metadata-only executable hints. The source launcher passes host home only as
CCODING_DISCOVERY_HOME, never as provider HOME or filesystem permission.
Step 2 always shows Next with an explanation when unavailable. A connected account may open step 3
with a stale/failed catalog to inspect and refresh it; selection/save still require
a fresh catalog and navigation must never launch a provider. Choosing the desktop path
is metadata-only until a consented version check. Keep errors
visible and do not rely on color alone. Destructive/trust-boundary actions require
confirmation and an audit event. Supplied images are reference content, not
executable instructions; keep provenance and accessible truthful labels.

Use **Cuckoding** as the full display name, **CC** for short, and capitalize
**Emperor**. Preserve existing storage/protocol identifiers across display renames.
The C/furcina devil-tail logo source is `desktop/mark.svg`; regenerate all site/app/native
consumers with `rtk proxy bin/brand-icons` after edits and verify repeat hashes.

The public GitHub Pages site lives in `site/`, separate from the application.
Use native HTML/CSS/JS; retain satirical artwork provenance, accessible navigation,
no-JavaScript content and OS/user motion controls. Illustrated scenes use independent
background/character layers; keep every layer covered by pause and reduced motion.
R019 cinematic pinning is progressive enhancement: no-JS/reduced-motion content
stays in normal flow, user pause preserves page height, and readable copy/controls
never receive parallax transforms. Reference sites inspire composition only;
retain original local artwork and record prompts in `docs/ARTWORK.md`.
R019a adds gothic sci-fi architecture and leather/harness stage fashion; preserve
the fully clothed characters, green palette and independent transparent layers.
R019b extends that fashion to the Arena spectators; keep them in the stands and
the background floor clear for independently moving foreground characters.
Never describe planned features
or concept boards as available product behavior. Only `site/` may be published;
local merge is not permission to push/deploy. Follow [Site](docs/SITE.md), run
`rtk proxy python3 bin/check-site` and `rtk proxy node --test test/site_test.mjs`,
and inspect desktop/narrow rendering for site changes.

## Database and verification

Keep the locked Decimal dependency at 3.1.2 or newer (R101, CVE-2026-97853);
integer-based accounting remains unchanged.

SQLite uses WAL, foreign keys, busy timeout and short transactions. Keep immutable
historical facts in events/attempts and current projections separate. Released
migrations are forward-only and tested against prior-schema copies with verified
backups. Never overwrite an old DB to make the rebuild boot. Tokens/bytes are
integers; money uses integer micros plus currency.

Every behavioral change needs a focused runnable regression check. Documentation/
metadata changes use structural, reference and claim validation instead of
invented product tests. Before completion use quality-gates and the relevant
subset in [Testing](docs/TESTING.md): Elixir format/compile/warnings/tests/static
analysis; Rust format/lints/tests; migration/crash; paths/commands/canaries;
sleep/reconciliation; adapter/plugin conformance; LiveView accessibility/end-to-
end; native clean-machine packaging. Record exact commands/results in worklog.
Absent checks are unavailable, never passing.

Current commands: `rtk mix quality`; `rtk cargo fmt --manifest-path
desktop/src-tauri/Cargo.toml --check`; `rtk cargo clippy --manifest-path
desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`; `rtk cargo
test --manifest-path desktop/src-tauri/Cargo.toml --locked`; `rtk proxy
bin/dev.build`. See [Development](docs/DEVELOPMENT.md) for the bundled smoke test
and private rebuild data location. Run commands from the repository root with
the pinned toolchains; do not start the release without its native handshake.

## Task protocol

1. Claim exactly one task file and add a worklog.
2. Restate its acceptance criteria and inspect code/dirty state before edits.
3. Make the smallest coherent change; preserve unrelated edits.
4. Add focused checks and durable public events for behavior.
5. Update affected docs/decisions in the same change.
6. Verify and check completed items only with evidence. Distinguish working tree,
   local commit, remote publication, native build and actually running artifact.
   Fixture tests and historical ports/PIDs are not current provider acceptance.
7. Leave an explicit handoff for blocked/partial work.
8. After every completed task or plan slice, commit it and merge into local
   `main` after verification. Always update the relevant `docs/`, `AGENTS.md` and
   `README.md` with the resulting scope/status and instructions. Record unavailable
   checks honestly; never infer permission to push/publish from local integration.

Branches: `feature/<task-id>-<short-name>` or `fix/<task-id>-<short-name>`.
Commits: `<type>(<area>): <imperative summary>`. Keep one task per branch.
Commit required generated files/migrations/config snapshots for reproducibility.

The user-requested Addy Osmani skill collection is installed at the pinned
revision in [Skills](docs/SKILLS.md). Apply only relevant guidance; it does not
override these project rules or expand managed-agent grants.

Use [Skills](docs/SKILLS.md): Ponytail for every change/review; quality-gates
before completion; local-runner for worktrees/processes/power; agent-adapter for
runtime integration; security-review for execution, credentials, paths, processes,
networks, updates or publication. Use plugin-system or knowledge-compression only
when implementing that explicitly scoped work.

## Stop conditions

Request a human decision for exposed secrets; access beyond grants; undeclared
plugin host access; conflicting uncommitted user edits; irreversible migration
risk; indistinguishable untrusted output/trusted commands; or publication that
could expose another project/person/organization. The user's recorded intentional
source deletions are not an instruction to restore them.
