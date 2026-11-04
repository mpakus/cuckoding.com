# BOSS working rules

@/Users/mpak/.codex/RTK.md

- Treat `BOSS_PLAN.md` as the product specification for this restart. Read
  `tasks/plan.md`, `tasks/todo.md` and the latest `.worklog/` entry before work.
  Earlier Cuckoding implementations are not requirements for BOSS.
- The 2026-11-02 autonomy revision is the development priority: minimize owner
  intervention and time to verified delivery. Ordinary questions and known-clean
  implementation/check/review failures should first receive another model's
  diagnosis and a fresh implementation attempt. Pin the model policy before effects,
  preserve acceptance criteria and show the resolution evidence. Measure successful
  autonomous delivery, not merely safe refusal. Historical requests keep their
  original policy; Stop and unknown execution ownership still stop dispatch.
  Change a shipped routing/budget contract through a new policy version; never
  reinterpret old requests or rewrite their model and approval evidence.
- Routing version2 pins a validated visible CLI catalog before agent stages; keep
  metadata discovery bounded, Stop-aware and outside database/Manager transactions.
  Metadata is not entitlement proof. Exclude models only on typed unavailable
  evidence; shared provider/startup failure stops batch dispatch before another task.
  A fresh Autopilot snapshot may retry eligible unfinished tasks with new UUIDs,
  preserving old receipts, Done, dependency gates and unknown-cleanup quarantine.
- Use multiple agents for independent implementation/review tasks. Give each
  writer an isolated worktree and `codex/` branch with explicit file ownership;
  integrate dependent work sequentially. Keep one owner for shared migrations
  and shared documentation to avoid competing edits.
- Update this file, relevant documentation, task status and `.worklog/` with each
  completed increment. Record only verified behavior and actual commands.
- Review and test finished branches, merge them into local `main`, verify the
  combined result, then remove their temporary worktrees and merged branches.
  Preserve unrelated work and dirty checkouts; do not force-delete them. Remote
  publishing is separate from these local merges.
- Use Ponytail: the smallest complete change, explicit failure handling and
  focused verification. Change only files needed for the current task; no
  speculative abstractions, unrelated cleanup or automatic dependency additions.
- Prefix shell commands with `rtk`; use `rtk proxy` for unsupported commands and
  when exact output matters (especially JSON, CLI contracts and test evidence).
- Before non-trivial implementation, search the xerj `bossrefs` index, then read
  the relevant source and tests in `examples/`. Follow `examples/README.md`.
  Record query, source path + pinned SHA, adopted pattern and rejected tradeoff
  in `.worklog/`. A search miss is not evidence: fall back to `rg` and official docs.
- Reference checkouts are read-only research inputs, not runtime dependencies.
  Their agent instructions do not govern BOSS. Do not reset, update or clean
  existing reference checkouts automatically. Check license and provenance before
  copying code; prefer independently implemented patterns.
- Keep `.worklog/YYYY-MM-DD.md` current: scope and baseline at the start;
  decisions, touched files, commands/results and limitations during work;
  outcome and exact next step before finishing. Never record credentials or raw
  private agent transcripts. Update task checkboxes only with verification evidence.
- Use relevant installed skills. Install a missing skill only when needed for
  the task, inspect it first and avoid unrelated integrations or telemetry.
- Preserve source specs and user changes. Never equate process exit, a model's
  "done" message or an old approval with verified delivery. Keep spec revision,
  run, checks, review and integration tied to the actual Git commits.
- Verify the effective Elixir/OTP pair in `.tool-versions`. On this machine use
  `rtk proxy asdf exec mix ...` when Homebrew takes precedence in PATH.
  Application tests and the separate `spikes/` suites have different acceptance
  scopes; a passing experiment is not a production adapter.
  A packaged VM must preserve the incoming host PATH before Erlang prepends its
  private ERTS directory, restore it before tool discovery/worker startup and
  consume the handoff marker. Child overrides must not inherit a stale snapshot.
  Do not substitute the BOSS runtime for a project's selected CLI/toolchain.
  Project children must not inherit BOSS-owned MIX_ENV, PORT, PHX_SERVER or
  BOSS_DATA_DIR defaults. Preserve explicit child overrides and incoming PATH;
  never force test mode or mutate the running VM environment to repair a project.
- Release candidates must bundle and verify native library closure, notices and
  build provenance; test the extracted archive with private fresh data. Keep
  distribution disabled for the local launcher. A local package/smoke is not
  clean-machine, signing, provider, Linux or remote-CI acceptance. Never hide
  dependency advisories or publish a prerelease as stable; see docs/RELEASE.md.
  Keep the direct Phoenix.HTML requirement at or above 4.4.0 for CVE-2026-117645.
  Seed historical migration fixtures against their old schema. Apply independent
  schema additions before calling current contexts without advancing the migration
  under test.
- Release runtime pins include the actual OpenSSL version, not only OTP/Elixir.
  Reject stale crypto before packaging; retain upstream notice provenance and
  native closure checks. This RC requires source-built OTP28.5.0.8 with static
  OpenSSL3.5.9; record OTP's MD5-only vendor component separately. Build runtimes
  in an isolated prefix; do not mutate the host toolchain to make a package pass.
- BOSS uses Apache-2.0 in root LICENSE. Preserve its exact text in release
  LICENSES/BOSS-LICENSE and retain separate third-party notices; reference licenses
  do not replace the project's chosen license.
- Signing is explicit and works on a copy: one Developer ID Team for every native
  image, hardened runtime and only BEAM allow-jit, followed by packaged smoke.
  Keep signing, notarization Accepted, stapling and clean-machine acceptance as
  separate evidence. Never bypass library validation/Gatekeeper or resubmit an
  unknown notarization outcome; reconcile its saved submission ID first.
  Keep unsigned BUILD_INFO/runtime hashes as assembly provenance; signing receipts
  bind the input archive and new DMG bytes. Native minimum-OS headers alone do not
  establish clean-machine or Gatekeeper acceptance.
  Validate the explicitly selected notarization Keychain profile before submit.
  A Developer ID certificate or account name does not prove the profile exists;
  a missing profile is a local credential preflight failure, not Apple rejection.
  Preserve upload authorization and never choose another account automatically.
  Diagnose profile visibility using invoking-user/keychain search metadata only;
  never enumerate credential payloads or guess another saved profile.
  Distinguish an Apple Account/app-password label from a local notarytool profile.
  Interactive credential helpers must inherit a real Terminal on all three streams;
  keep RTK around launch operations, not between that TTY and Apple's prompt.
  Retain only exit/TTY receipts, never terminal I/O or supplied account addresses.
  An app-password label cannot authenticate: the owner enters the generated value
  only into Apple's private prompt; never request that value in chat.
  A profile-save confirmation helps locate credentials but is not readiness proof;
  revalidate that selected profile in the current Keychain before upload effects.
- Remote RC evidence must distinguish PR head, tested merge SHA and packaged
  BUILD_INFO. Keep opt-in provider budgets outside model-writable paths, preserve
  the selected account and leave cleanup time inside the deadline. A failed paid
  acceptance run never authorizes an automatic second workflow or CI provider call.
- LiveView test async drains use explicit bounded render_async(view, 2_000) waits.
  Search every caller across test/, retain assertions/loop counts and intentional
  timing checks, and never raise global ExUnit or production deadlines for CI.
- Async fixture replies after persistence use explicit bounded waits and match the
  actual worker. Preserve intentional Stop/deadline and exclusion assertions;
  do not replace all mailbox waits or change a production timeout to fix a fixture.
- Create test scratch roots exclusively before registering recursive cleanup.
  A VM-local counter is not a globally unique directory name. Never remove a
  pre-existing directory to make a test pass.
- Hold the data-directory lock in Application callback state until all children
  stop. Initialize SQLite WAL before starting the two-connection Repo pool;
  Ecto migrations require at least two connections. Tests must use fresh data.
- For an independent local build/run, preserve an occupied port's server and data
  unless its restart/backup is explicitly authorized. Use a free port and fresh
  private data; keep bootstrap tokens only in the owner's Terminal.
- Tie local failure evidence to the serving port and data root. A legacy database's
  failed attempts are not fresh-instance runs; a passing current preflight never
  rewrites an earlier blocked batch or approves an old changed candidate.
- Keep local tokens out of URLs and persistent logs. Preserve `same-origin`
  referrer policy: `no-referrer` made legitimate browser form POSTs send a null
  Origin. Continue rejecting foreign/null origins; do not weaken the allowlist.
- Token recovery uses the owner-local IEx `Boss.LocalAccess.new_token()` or an
  authorized idle-instance restart with consistent backup/original data. Local
  console operations use public Manager APIs and saved UUIDs; browser observation
  still requires authentication. Never capture Terminal I/O or enable RPC for it.
  A console requester's terminal receipt is not worker completion. Check the
  saved stage/review evidence; exhausted cycles and changes_requested keep the
  task Blocked and its following Backlog gate closed even when checks passed.
- Repository/specs paths come from the native folder chooser, never editable
  form paths or browser file-upload names. Keep the selection server-side and
  revalidate it on registration. Resolve relative specs against the selected
  repository; preserve cancellation and bounded, single-dialog helper cleanup.
- Record spec identity, append-only revision and initial task atomically with an
  immediate SQLite transaction. Compare with the latest revision, not any older
  matching hash; A→B→A must retain all three. Keep task revision/title pinned.
  Direct record calls reject ID/path conflicts; the full importer reconciles moves
  and path swaps. Missing history may share a path, but present specs may not.
  Keep composite revision ownership and immutable-history database constraints.
- Import only complete validated scans; scan and reconciliation share an immediate
  transaction. Bound traversal, bytes, YAML and worker count/time/memory. Keep
  workers supervised and bound to the actual Repo PID. Interrupted outcomes may
  already be committed: reload persisted entries, never promise rollback on timeout.
  Preserve raw source; reject ambiguous YAML types/aliases and raw non-UTF8 names.
- Automatic refresh uses one owned sequential sweep, with the next timer armed
  after completion or failure. Resolve Repo once per sweep; never let an old sweep
  resolve a replacement Repo. Compare exact present identity/path/source sets;
  unchanged polls must not write timestamps. Changed automatic scans must settle.
- Publish successful results only after transaction return. Equal counts may describe different
  changes: never suppress successful notifications by count equality. Subscribe UI
  before reading and coalesce entry reloads; cached success must not hide interruption.
- Test committed durability/concurrency in an exclusively created scratch DB with
  a real connection pool; a sandbox transaction alone is not restart evidence.
- Apply task commands through `Boss.Tasks.transition/2`: expected version plus a
  task-scoped command ID, one task/event transaction, immutable receipts. Replay
  returns the original event, not the current task. Pin the actual Repo PID for
  the whole command and restore the caller's selector; never cross a Repo restart.
  Retry unknown storage outcomes with identical input and the same command ID.
- Keep producer-dependent transitions closed until persisted commit-bound evidence
  is implemented. Caller-provided flags/verdicts are not evidence. Recovery uses
  the saved target, never a caller-selected state; only `done` satisfies dependencies.
  See `docs/TASK_WORKFLOW.md` for commands and the read-only board contract.
- Read task details through a project-scoped query and one Repo-pinned read
  transaction. Keep source revisions immutable; bound event reads to the latest
  50. A selected historical revision never changes the task snapshot.
- The URL owns drawer/task/revision selection. Coalesce refresh reads and reject
  stale results; never show cached source for a different desired revision.
  Preserve native dialog modality/open state across patches, restore card focus
  on close and synchronize a focused revision select after history navigation.
- Agent discovery executes only fixed version/help and advertised local status
  commands from BOSS's PATH, outside project repositories. Never read auth files
  or retain raw probe/account/key output. A configured CLI status is not verified
  model access; advertised help flags are not a working adapter or usage proof.
- Keep detection explicit, one scan at a time, with bounded time/output and
  requester-owned direct-child cleanup. Do not claim wrapper-descendant cleanup
  or promote this metadata probe into the production runner.
- Keep stream EOF distinct from process exit and forced pipe closure. Demand must
  bound upstream queues; Stop and absolute cleanup deadlines must work while the
  consumer is stalled. A direct-PID watcher or leader exit is not tree cleanup.
  An integer exit code such as 137 alone does not prove signal termination.
  Keep fixture transport experiments isolated until lifecycle/recovery gates pass.
- Live provider calls are opt-in and bounded; never repeat a paid smoke run
  automatically. Retain sanitized evidence, not raw private transcripts.
- Git publication must not move a branch behind a user's checkout. The spike
  refuses an already checked-out target and retains failed/dirty worktrees.
  The Exile fixture experiment verifies demand/EOF only; its own production
  integration, descendant cleanup and durable recovery remain open gates. erlexec may report
  exit 0 after cancellation: retain the cause.

- Manual Codex attempts are separate from task state: persist admission and pinned
  workspace intent before effects; command replay must return the saved attempt
  even while another runs. Keep one global active/unknown attempt. Never call a
  CLI terminal event task approval, Done, or integration evidence.
- The macOS native guardian owns a fresh process group, retains the leader until
  group cleanup, and distinguishes exit, signal, EOF and forced closure. Credits
  and Stop control writes must retry boundedly under stdin backpressure. Detached
  sessions are outside this guarantee; lost helper/Repo receipts quarantine runs.
  Only the parent assigns PGID before releasing the pre-exec gate; concurrent
  parent/child setpgid calls can fail with EPERM on macOS.
- A valid terminal guardian receipt retires every pending ACK/Stop control write.
  Continue waiting for actual helper exit0; nonzero/lost helper status stays unknown
  even after a receipt. Do not confuse helper status with the CLI's own exit code.
- Retry the final native child reap only for EINTR within the existing absolute
  cleanup/natural deadline; require the actual saved child PID to be returned.
  Other errors, persistent interruption, expiry and query uncertainty stay unknown.
- Stop must reach the live project-scoped worker without waiting on the Repo or
  Manager mailbox. Browser/requester death must not own the run. Repo loss kills
  the worker; restart never reuses a saved PID or automatically respawns work.
- Recovery must notify connected pages after committed top-level changes, once
  per affected project; no-op, nested transaction or rollback must stay silent.
  Preserve unknown-cleanup quarantine and show it honestly; waiting or restarting
  does not resolve it. See docs/RECOVERY.md for evidence and remaining gates.
- Preserve completed Ready evidence across restart; a paused Autopilot must reject
  even its saved integration UUID until explicit Resume. A report artifact plus
  terminal CLI text without exit/EOF/cleanup is still unfinished. Confine crash-test
  TMPDIR to its exclusively owned scratch root; do not sweep unrelated temp files.
  Recheck candidate files/ref and target ancestry after restart, including edits
  hidden by index flags. Offline Git changes never rewrite the original approval.
- Keep Codex source on stdin, workspace-write sandbox and explicit Start. Persist
  only bounded event types/counts/usage, never raw model/tool/stderr text. Test
  production transport with finite fake CLIs; paid/provider calls remain opt-in.
- Pin the managed reviewer before effects; changing Codex/Claude with the same
  command UUID conflicts. Existing deliveries default to Codex. Claude is an
  evidence-only reviewer with no model filesystem/shell tools, fresh scratch cwd
  and stdin input; its internal StructuredOutput formatter is expected. Validate
  the terminal structured result plus transport and candidate identity. Never
  fall back to another provider or treat Claude CLI permissions as an OS sandbox.
  Host-managed startup policy remains outside ordinary hook/settings suppression.

- Managed deliveries own task progress through persisted plan/stage evidence;
  manual run/check/review receipts remain advisory. Save each intent before effects,
  pin original spec/base/plan/config and link every snapshot/check/review. Ready
  requires full criterion coverage; Done requires explicit exact-SHA publication,
  passing postchecks and verified retained checkout. Never accept caller-selected
  state or insert completed delivery/stage rows to bypass these gates.
- Explicit review retries create a new delivery/UUID from an immutable rejected
  review. Preserve original spec/base/config/reviewer and exact acceptance strings;
  revalidate the retained candidate. Pin the parent's committed terminal task event
  (terminal delivery.task_version is the preceding version). Fresh cycle0 snapshot
  and check must supply complete transient output before fixes; never manufacture
  old output or inherit approval. Preserve the parent's saved autonomy policy:
  legacy has three cycles/twenty stages; version 1 has five cycles/forty-eight stages.
- Explicit implementation-timeout retry pins a new execution_recovery_version1
  and source implementation/terminal event before effects. Preserve old policy0,
  original plan/criteria/spec/base/checks/reviewer/catalog and immutable failures.
  Retained-plan adoption is typed provenance, never invented CLI/approval evidence.
  Save partial-snapshot intent before Git, then fresh checks and a distinct-model
  resolver before replacement implementation. Only confirmed timeout with known
  cleanup/EOF qualifies; Stop and unknown stay closed. Keep five cycles/48 stages,
  full original-base review and exact publication/postcheck gates. No old batch
  or task is reopened by replay. See docs/AUTONOMY.md.
- Candidate retry after Failed requires an explicit full commit SHA, the latest
  historical rejection, a later passing final check and a matching terminal event.
  Pin the selected SHA separately from the old review SHA and prove ancestry
  before provider effects. Keep historical findings distinct from fresh approval.
- Explicit checkpoint recovery pins a new checkpoint/source-check and implementation
  network policy before effects; retain original spec/criteria/base/checks/reviewer.
  Preserve old terminal attempts and policy0. Capture the exact retained candidate,
  run fresh checks, and resolve before replacement implementation. A known-clean
  actual check timeout may feed diagnosis only after fresh candidate verification:
  preserve timeout/incomplete-output evidence, use no invented output/hash or approval.
  Stop, unknown cleanup, output-limit failures and changed candidates remain closed.
  Final review/publication/postchecks still require complete passing checks.
  Implementation network policy1 keeps workspace-write, uses an immutable explicit
  package-host proxy policy and local-binding support; the latter permits broader
  local/private access, not only one PostgreSQL port. Read-only stages and old
  requests retain their prior policy. Never let model-written files expand hosts,
  change host settings or replace the sandbox with full access.
- An explicit checkpoint can recover a retained implementation after a typed
  provider rate limit. Pin `provider_recovery_version: 1` on the new request.
  Require the saved terminal task event, natural nonzero exit, both EOFs, known
  cleanup and exact implementation workspace. Save capture intent before Git,
  then check, diagnose and implement before fresh review. Provider failure
  still stops dispatch.
- Documentation projects use one explicit persisted intake before Autopilot.
  New planning_version1 retains at most three immutable model attempts under one
  absolute deadline. Save model/source intent before effects and sanitized receipt
  before handoff; bind generated tasks to the latest successful plan hash. Preserve
  legacy0 and failed requests. Stop, unknown cleanup, source drift and shared
  provider failures halt; replay never starts another attempt.
  Pin the committed source and target before the read-only planner. Validate the
  full dependency graph and source paths. Save derived tasks and their batch
  together, keep them outside filesystem import reconciliation, and verify the
  initial Git base again at first dispatch. Stop must survive the handoff.
- Converting a populated specs project to documentation mode is an explicit idle
  metadata command: seal exact imported task/revision/version membership atomically
  and preserve old states/history. Reference tasks remain readable but cannot accept
  new execution, check/review, adoption or integration intents; saved UUID replay
  precedes that gate. Refuse active/unknown work and retained publication intent.
  Conversion never calls a model. Namespace subsequent generated IDs, dependencies
  and paths by intake UUID, reject collisions, and retain ordinary Done evidence.
- Queue only explicit saved workflow requests: pin revision/version/checks/reviewer
  and UUID before effects, claim and link a delivery in one immediate transaction.
  Replay/cancellation must precede dispatch; never silently turn direct Start into
  queue authorization. Pending requests block same-task Start and source adoption.
  Pause unstarted requests on restart; Resume retains the original inputs. A
  started request never returns to the queue or automatically respawns a stage.
- Autopilot requires an explicit whole-current-Backlog snapshot (present New tasks,
  max256), immutable request links and integration UUIDs. Replay precedes readiness;
  require every member before dispatch. Only one task runs at a time, regardless
  of saved worker capacity. Bound dependency sweeps without waiting writes; reset
  the sweep cursor after Resume. Pause prevents
  new tasks/integration but lets admitted work finish. Stop withdraws the batch and
  signals its owned worker directly. Restart pauses. A pre-integration failure,
  block or clarification with known cleanup releases only the execution slot;
  it never satisfies dependencies
  or retries that task. Stop, unknown cleanup and integration failures still halt.
  Keep the intake base pin until the first verified Done. Check target
  availability before model effects and at publication.
  See docs/AUTOPILOT.md; ordinary Start/Queue never imply automatic integration.
  For an explicitly requested checked-out-target repair, inspect every worktree
  and preserve files/ref tips. A clean checkout can move to a new observer branch
  at the same commit; keep it off the target while Autopilot integrates.
  Check the serving data root and saved base branch before repairing a recurrence.
  A fresh registration defaults to the branch checked out at registration time. A blocked
  batch needs a fresh explicit Start, never an automatic paid retry.
  Reconcile an uncertain Start only with its exact committed batch and pinned
  inputs. Drain a refresh received during the action; stale or unrelated reads
  cannot unlock it. An active confirmed batch must restore Stop without dispatching again.
  For owner-ordered task-then-Backlog acceptance, verify that task's exact
  publication/postchecks/Done before starting the next Autopilot snapshot.
- Persist global managed capacity 1–3 (default two); compare settings versions and
  refuse shrink below actual owned workers until EXIT. Context, Manager and SQL
  must use the same saved capacity; manual execution and integration stay exclusive.
  Keep one bounded rotating queue sweep and no writes for unchanged waiting state.
  Unknown cleanup is a global admission barrier, but its failure receipt must be
  persistable while a peer still runs. Match completion/EXIT to the owned ID/PID;
  Repo loss stops every owned worker, normal Stop affects only its selected one.
  Typed file scopes are predictions, never write permissions or correctness proof.
  See docs/WORKFLOW_QUEUE.md.
- Preserve missing/null legacy scopes as unknown. Validate bounded literal relative
  file/directory predictions; reject ambiguous JSON, glob/dot/parent/.git paths.
  Acquire scope admission with the first implement step in an immediate transaction;
  compare saved repository identity and active acquired claims, never planning-only
  peers. Hold through fixes/checks/review. Use one SQL overlap policy for context,
  UI and database guards; serialize non-ASCII known paths conservatively. Waiting
  must not write timestamps or rerun a model; direct Stop and Repo-loss cleanup remain
  available. Unknown predictions never imply safe parallel changes.
- Coordinate BOSS Git worktree metadata operations by the actual common directory
  within this VM. Keep lock waits bounded and Stop-aware; lock release is not
  native cleanup or external-Git exclusion. Preserve unknown-outcome quarantine.
- Concurrent worktrees/candidates may share newly created parent directories.
  Accept mkdir EEXIST only after fresh lstat confirms a real directory; preserve
  existing modes and reject files/symlinks. Propagate failed chmod. Keep UUID
  scratch/report directories exclusive. Test Manager timers must end before their
  Sandbox owner. Fixture teardown removes every registry alias owned by its exact
  worker PIDs and resets both queue cursors; never rescue ownership errors in
  production to hide fixture leaks.
- Shared Sandbox's single checkout is not a real two-connection concurrency pool.
  Keep capacity-only UI fixtures phased without weakening live UI/peer assertions;
  correlate completion with the actual worker and restore suspended views in after.
- Fixes get complete transient check output/receipt and prior feedback in a fresh
  worktree at the rejected candidate; review the full original-base diff. Version 1
  resolves known-clean questions/failures and changes implementation model before
  exhausting its five-cycle/forty-eight-stage budget. Legacy retains three cycles/twenty
  stages and repeated-failure refusal. Stop, changed candidates and unknown cleanup
  still halt. Do not persist raw output or truncate prompts to manufacture approval.
- Terminal workflow attention uses the persisted task event for the reason and
  recovery action. Derive it from bounded structured findings and fixed stage
  diagnostics. Strip controls, preserve UTF-8 and never include raw output.
  Notify connected boards once per task version. Older receipts remain immutable.
  A typed planner question first enters version 1 resolution before owner attention;
  retain a retry's approved scope and distinguish missing decisions from code defects.
- Fresh check worktrees must install actual locked dependencies through the explicit
  repository check command; never vendor dependencies or exclude the real adapter
  from tests to manufacture a passing check. Oversized review input remains a
  closed gate; keep the full original-base diff within bounds without truncation.
- Give planning and implementation the saved check configuration before execution.
  Preserve candidate-change diagnostics through the final failure and display old
  failed-stage receipts without rewriting them. Exit zero with changed files/HEAD/ref
  remains a failure; never silently exclude generated paths or ignore source/tests.
- Unchanged-target integration fast-forwards the original approved candidate.
  An advanced target needs immutable merge/check/fresh-review stages, all kept
  `integrating`; preserve the original approval. Pin target and selected reviewer,
  reject rewritten history and stop on new drift/conflict/failure without retry.
  Only the new exact merge lineage can authorize its publication. Reserve an ordinary
  BOSS-owned target worktree, reject user-checked-out targets, authorize immediately
  before expected-old-SHA CAS, rerun saved checks, then detach only that owned
  checkout without deleting files. Postpublication failure retains the target and
  evidence; unknown receipts quarantine, never automatically retry/reset.
- Construct merge candidates with exact commit IDs, merge-tree exit success and
  ordered parents `[target, approved candidate]`. Never accept a conflict tree,
  mutate a user index/checkout or execute configured external merge drivers.
  Retain fresh refs/workspaces and verify exact parent/ref/HEAD/tree identity.
- Revalidate persisted review reports before authorizing publication. An approved
  report requires complete passed criteria and an explicit empty issues array;
  SQL guards must reject nonempty, absent, null or incorrectly typed issues.
  A merge candidate must have a fresh check ID/path/ref, never the original one.
- Preserve external task cancellation without poisoning the outer transaction.
  A new explicit workflow can retire a stale Ready approval; never reuse it.
  Clear UI Stop state after a persisted inactive delivery so later integration
  of the same delivery retains a working Stop. See docs/MANAGED_DELIVERIES.md.
- New managed/manual starts check dependencies inside their admission transaction,
  after replay and before effects. Resolve literal explicit IDs only within the
  project, from every task's pinned source; never infer filenames or use latest
  revisions. Only Done satisfies an edge. Retained missing Done is valid; missing
  unfinished prerequisites, invalid declarations and reachable cycles block.
- Adopt source revisions only through a project-scoped `adopt_revision` task
  command with fixed target, expected version and immutable command ID. Preserve
  both old/target revisions in the event and all earlier run/check/review history.
  Atomically reset an eligible idle task to New and retire unintegrated Ready
  approval. Never reopen Done or hide active/unknown work or an unfinished
  integration intent. Historical manual checks/reviews keep their parent pins.
  Selecting a source is read-only; uncertain adoption retries the original command.
  Publish notifications only after committed top-level success. See docs/TASK_REVISIONS.md.
- Keep dependency graph reads bounded and lazy; refuse limits instead of accepting
  partial readiness. Preserve YAML sequence/map types, including [] versus {}.
  Dependency reads never mutate task state. Unknown start requests must still
  reconcile the same UUID even if readiness changed. Existing saved checks/reviews
  are independent of the new-start gate. See docs/TASK_DEPENDENCIES.md.

- Manual checks execute only explicitly entered user argv, never commands inferred
  from model/spec/config text. Retain normalized argv/config hash and source run;
  replay with another adapter/source/command is an idempotency conflict.
- Capture checks with private Git indexes into a new retained commit/ref and
  detached worktree. Preserve original run index/HEAD/files. Persist intent before
  Git and candidate SHA before command execution. Verify exact clean HEAD/ref and
  fresh reconstructed tree before/after checks; index flags cannot hide edits.
- A passing check requires candidate SHA, actual exit 0, both EOFs, known group
  cleanup and unchanged tree. It applies only to that commit/command, never future
  edits or task Done. Codex/checks share global admission, Stop and quarantine.
- Keep source Codex parents accessible exactly once after truncating check history;
  deduplicate parent identities before subtracting recent IDs. An unknown
  UI start retries identical argv and UUID; persisted receipts resolve uncertainty
  even if the admission reply arrives late. Never persist raw check output.
- Manual reviews pin the passed check's candidate, config and spec; use a fresh
  read-only Codex session and verify the same candidate before/after. Never infer
  final review from a JSONL message or exit alone: validate the CLI last-message
  artifact only after protocol completion, EOF and known cleanup.
- Bound review input/report size without truncation. Preserve JSON object pairs
  until duplicate/unknown keys are rejected; require criterion/issue consistency.
  Keep execution status separate from model verdict and task approval/Done.
- Hold the exclusively created report file descriptor and reject replacement paths.
  One monitor owns cleanup and atomically invalidates the CLI path before unlinking;
  filesystem failure or whole-VM crash can leave a temporary artifact. Never store
  raw stream text. Preserve both source levels
  (review -> check -> Codex) exactly once in bounded history.

- The public Cuckoding marketing page is the standalone `site/` GitHub Pages
  artifact. Keep its claims tied to current BOSS evidence, label illustrative
  workflows, preserve reduced-motion/no-JS access and relative assets. Validate
  with `scripts/check_site.py` and `test/site_motion_test.mjs`; do not deploy the
  application or imply signing/provider/Linux acceptance from a website check.
  See docs/SITE.md; remote publishing remains separate from local merges.
  Additional satire artwork must preserve readable human–machine interactions at
  narrow widths; share the existing motion control and retain image provenance.

- Website-only publication must start from freshly fetched remote main, use an
  explicit website/check/documentation path allowlist, and verify commit ancestry
  before pushing. Never push the local BOSS main for a site-only request. Verify
  the exact Pages run and live HTTPS bytes; retain publication SHA/run evidence.

- Keep the application aligned with the marketing visual system in
  `docs/UI_DESIGN.md`: semantic paper/ink/sage/peach tokens, compact task evidence,
  native drawer/focus behavior and document-level motion controls. Verify narrow
  layouts and keyboard/reduced-motion behavior without triggering real work.
