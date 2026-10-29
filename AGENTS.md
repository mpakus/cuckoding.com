# BOSS working rules

@/Users/mpak/.codex/RTK.md

- Treat `BOSS_PLAN.md` as the product specification for this restart. Read
  `tasks/plan.md`, `tasks/todo.md` and the latest `.worklog/` entry before work.
  Earlier Cuckoding implementations are not requirements for BOSS.
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
- Release candidates must bundle and verify native library closure, notices and
  build provenance; test the extracted archive with private fresh data. Keep
  distribution disabled for the local launcher. A local package/smoke is not
  clean-machine, signing, provider, Linux or remote-CI acceptance. Never hide
  dependency advisories or publish a prerelease as stable; see docs/RELEASE.md.
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
- Remote RC evidence must distinguish PR head, tested merge SHA and packaged
  BUILD_INFO. Keep opt-in provider budgets outside model-writable paths, preserve
  the selected account and leave cleanup time inside the deadline. A failed paid
  acceptance run never authorizes an automatic second workflow or CI provider call.
- LiveView test async drains use explicit bounded render_async(view, 2_000) waits.
  Search every caller across test/, retain assertions/loop counts and intentional
  timing checks, and never raise global ExUnit or production deadlines for CI.
- Create test scratch roots exclusively before registering recursive cleanup.
  A VM-local counter is not a globally unique directory name. Never remove a
  pre-existing directory to make a test pass.
- Hold the data-directory lock in Application callback state until all children
  stop. Initialize SQLite WAL before starting the two-connection Repo pool;
  Ecto migrations require at least two connections. Tests must use fresh data.
- Keep local tokens out of URLs and persistent logs. Preserve `same-origin`
  referrer policy: `no-referrer` made legitimate browser form POSTs send a null
  Origin. Continue rejecting foreign/null origins; do not weaken the allowlist.
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
- Queue only explicit saved workflow requests: pin revision/version/checks/reviewer
  and UUID before effects, claim and link a delivery in one immediate transaction.
  Replay/cancellation must precede dispatch; never silently turn direct Start into
  queue authorization. Pending requests block same-task Start and source adoption.
  Pause unstarted requests on restart; Resume retains the original inputs. A
  started request never returns to the queue or automatically respawns a stage.
- Autopilot requires an explicit whole-current-Backlog snapshot (present New tasks,
  max256), immutable request links and integration UUIDs. Replay precedes readiness;
  require every member before dispatch. Only one task advances through verified
  Done before another starts, regardless of saved worker capacity. Bound dependency
  sweeps without waiting writes; reset the sweep cursor after Resume. Pause prevents
  new tasks/integration but lets admitted work finish. Stop withdraws the batch and
  signals its owned worker directly. Restart pauses; terminal failure halts without
  fresh retries. Check target availability before model effects and at publication.
  See docs/AUTOPILOT.md; ordinary Start/Queue never imply automatic integration.
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
  worktree at the rejected candidate; review the full original-base diff. Maximum
  three cycles; repeated unchanged failure, invalid input, Stop or unknown cleanup
  halts. Do not persist raw output or truncate prompts to manufacture approval.
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
