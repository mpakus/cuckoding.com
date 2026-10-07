# Worklog — 1057 autonomous project flow

- Date: 2026-09-30
- Task: [1057](../tasks/phase-10-hardening-beta/1057-autonomous-project-flow.md)
- Status: in progress; full AU-01–AU-05 scope retained
- Branch: `feature/1057-autonomous-project-flow`
- Base: `a04abe2548ee0838f625adaeeaab4b34bd345560`

## Acceptance and boundaries

Implement Agents once → project brief → reviewed plan → Run → verified working
local result. No routine task import, per-task approval or retry intervention.
Keep durable SQLite state, independent Review, finite authorization, ownership
checks, immutable snapshots and separate release approval. Track every remaining
milestone in the task; fixture checks alone do not prove provider/native behavior.

## Initial inspection

- Existing task-1056 plan is staged by the user; PLAN/reference metadata and
  research task/worklog are also present. Preserve their staging and contents.
  Plan index blob at task start: `8ece06c315a8dbe530a4d6e22e23d84e773f58b9`.
- Read the adoption plan and required product, architecture, database, flow,
  security, execution and reference-coding contracts. Reusing existing
  ProjectOnboarding, provider accounts, BoardControl/Plans and durable events.
- Skills: Ponytail 4.10.0 (MIT), repository minimalism, architecture, workflow,
  Phoenix/LiveView, security review and quality gates. No new dependencies.
- Shell commands are RTK-prefixed. `rtk proxy` is used for exact source streams,
  line evidence and structured validation where output filtering hides details.
- Pinned Paperclip research remains task 1056's MIT checkout. Relevant patterns:
  onboarding-seed.ts:361/393 for revision/idempotency/transactional audit;
  execution-recovery-attempt.ts:43/59 for distinct failure/continuation counters;
  native-runtime/completion-contracts.ts:124 for criterion-bound evidence.
  Adapt behavior only; no copied upstream code or extra engine.

## Progress and verification

Implementation and evidence are recorded below per milestone. No commit, push,
merge, native build, restart or real-provider run has occurred. Asset compilation
and fixture subprocess execution are recorded separately.

### AU-01 implementation

- Added append-only default-team revisions, saved-agent reference validation,
  fixed built-in role grants, finite profile validation and transactional audit.
  Project registration copies defaults and records the hash/revision; stale UI
  setup and changed runtime references fail before repository initialization.
- Added the accessible default-team form to Agents. Activity refresh retains
  unsaved instructions. Settings affect new projects only; no provider fallback.
- `rtk env -u CR_PAT mix format` on changed Elixir files passed.
- `rtk env -u CR_PAT mix compile --warnings-as-errors` passed at this milestone.
- Initial focused tests: 20 tests, one expected old-copy assertion failed after
  changing the setup text. Updated that assertion to the new visible contract.
  Focused re-run result follows. Migration compilation emits the existing test
  pattern's module-redefinition warning; it is separate from app compilation.

- `rtk env -u CR_PAT mix test test/cuckoding/project_onboarding_test.exs test/cuckoding_web/agent_settings_live_test.exs test/cuckoding_web/project_setup_live_test.exs test/cuckoding/shared_authorization_migration_test.exs` passed: 20 tests, zero failures.

### AU-02 and AU-03 progress

- Added one project delivery entry point and an idempotent default board command.
  Browser reconnect loads persisted preparation; LiveView is not an execution
  owner. The read-only existing controller now derives criteria/assumptions,
  independently reviews the plan and imports Draft tasks automatically.
- New version-3 snapshots authorize preparation only. `ready_to_run` waits without
  dispatch; direct preparation, local completion and Resume cannot bypass Run.
  Brief edits consume a bounded revision and require fresh review. Discard retains
  history. Run binds the accepted plan/brief/team/policy/base/profile in a separate
  immutable authorization; the initial snapshot remains unchanged.
- Added the project UI, dashboard/settings entry links, safe Stop confirmation,
  saved form/disclosure state and a migration rejecting authorization rewrites.
- Added one durable UTC admission deadline across planning, waiting and delivery.
  Remaining time bounds each process timer, while existing measured active/wall/
  sleep accounting remains separate. Shared process launch checks the deadline;
  exhaustion stops only owned work, and uncertain cleanup remains explicit.
- Source review found the old evidence bundle treats the QA stage as one passing
  test. AU-05 must replace that for new goals with actual command results and final
  criterion/integration verification. Do not present existing QA evidence as that
  stronger proof. Trusted bootstrap/test/build preflight is also still outstanding.

### Verification so far

- `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs` passed at the preparation milestone: 33 tests, zero failures. The initial new negative test expected board ownership rejection while the task was still Draft; corrected it to verify both Draft rejection and a deliberate Ready-state bypass attempt.
- `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs:218` passed: one project Describe/Run/reconnect LiveView test. It caught and fixed a nil/boolean guard in the new empty-project screen.
- `rtk env -u CR_PAT mix test test/cuckoding/project_onboarding_test.exs test/cuckoding_web/agent_settings_live_test.exs test/cuckoding_web/project_setup_live_test.exs test/cuckoding/board_control_test.exs test/cuckoding/shared_authorization_migration_test.exs test/cuckoding_web/status_live_test.exs` passed before adding the deadline: 60 tests, zero failures.
- The first deadline/controls/migration run had 47 tests with one new fixture failure: the manually prepared delivery task had not been transitioned to Ready. Corrected the fixture to preserve the real preparation contract.
- `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs:284` then passed: one deadline test. It verifies no process callback after exhaustion and no fresh allowance on a replayed preparation key.
- `rtk env -u CR_PAT mix compile --warnings-as-errors`, `rtk env -u CR_PAT mix format --check-formatted`, `rtk env -u CR_PAT mix credo --strict`, and `rtk env -u CR_PAT mix sobelow --config` passed at this checkpoint. Initial Credo findings were addressed by explicit transaction helpers and simpler guards; no lint exemptions added.
- `rtk env -u CR_PAT mix assets.build` passed (Tailwind and esbuild); this is not a native bundle build.
- `rtk node --test test/task_board_motion_test.cjs` passed: one check for state motion, reduced motion, focus, normal updates and cleanup.
- `rtk git diff --check` passed. The user's staged adoption plan blob is still `8ece06c315a8dbe530a4d6e22e23d84e773f58b9`.
- Final checkpoint command: `rtk env -u CR_PAT mix test test/cuckoding/project_onboarding_test.exs test/cuckoding_web/agent_settings_live_test.exs test/cuckoding_web/project_setup_live_test.exs test/cuckoding/board_control_test.exs test/cuckoding/shared_authorization_migration_test.exs test/cuckoding_web/status_live_test.exs test/cuckoding/run_control_test.exs test/cuckoding/execution/scheduler_test.exs test/cuckoding/workflows/state_machine_test.exs test/cuckoding/walking_skeleton_test.exs` passed: **101 tests, zero failures**, 58.2 seconds. This covers the final deadline/cleanup version as well as setup, preparation, UI, migration, launch controls, scheduler and delivery compatibility.
- Documentation path validation caught the nonexistent `test/cuckoding/workflows/state_machine_test.exs` argument in that exact historical command; Mix had ignored it. It is **not** transition-property evidence. Ran the real entry point separately: `rtk env -u CR_PAT mix test test/cuckoding/state_machine_test.exs` passed **2 properties and 4 tests, zero failures**.
- An inline `rtk proxy python3 -` structural check passed nine task/implementation documents, 41 local Markdown link paths, fences, whitespace and unchanged staged-plan blob. It checked file paths rather than heading anchors. The initial named-test inventory check exposed the incorrect historical path above; that correction is retained explicitly rather than rewriting the executed command.

### Remaining implementation — goal stays active

1. Finish AU-03 trusted bootstrap/test/build command preflight and bind displayed,
   validated declarations to Run; avoid executing free-form model text or changed
   repository policy. The saved time/task/revision limits must remain cumulative.
2. Implement AU-04 typed provider waits/transient failures and bounded productive
   continuation with separate persistent counters, ownership checks, backoff and
   useful exception details. Ordinary assumptions should stay with the team.
3. Implement AU-05 full brief/criteria context in every role, hash-bound actual test
   evidence, final integration Reviewer/checks and bounded repair; expose the usable
   local result. Legacy evidence/schema/flows must remain compatible.
4. Finish broader regression/security/provider tests and rendered/native acceptance,
   including actual zero-input correction/outage and physical sleep/restart gates.
   No authenticated provider run, installed-app check or physical recovery evidence
   exists for this task yet. No production data migration was performed.

## Command evidence and final-goal checkpoint

Acceptance for this increment: Run must freeze validated setup/check declarations;
all delivery roles must retain the original criteria; host check receipts and a
separate final Reviewer must gate Done at the exact reviewed head. Failed checks
must return to bounded reviewed repair without another Run. Preserve historical
task evidence and release boundaries.

- Reused `CommandPolicy` parsing/path validation and `LocalProcessRunner` ownership,
  minimal environment, redacted logs, deadline and cleanup. `GoalChecks` restricts
  declarations to supported installed developer tools, rejects shell/inline programs,
  outside argument paths, duplicate names and missing check commands. The pre-Run
  view shows resolved command arrays and discloses host execution/dependency setup.
- Run freezes commands separately from the initial planning snapshot. Later plans
  cannot alter that authority. Command events retain digests rather than raw process
  arguments. Structured configuration uses `command` arrays; the existing blanket
  `argv` diagnostic-redaction rule remains unchanged. This is authorized repository
  command execution on the host, not an OS sandbox.
- Added `final_review` to the existing controller, using the saved independent
  Reviewer and a fresh worktree at the final reviewed commit. Host checks retain
  exit/timeout status, process ID, log hash, authorization digest and head. Same-run
  replay uses completed receipts; a started command without a result stops instead
  of being repeated. Protected-path changes remain a separate approval boundary.
- Final acceptance requires every criterion exactly once, matching host records,
  intact logs, passing commands and the same clean Git head. A failed command or
  generated dirty file goes back to a reviewed repair plan within existing cumulative
  revision/task/time limits. Ordinary task settlement alone cannot mark the new
  goal Done. Late controller results also recheck the goal deadline.
- Every delivery stage and conversation handoff now includes the original brief,
  current authorized criteria and task mapping. New task bundles use schema 2 and
  an empty test list; a passing Review is no longer represented as a passing test.
  Loading prepared-task evidence verifies its authorization context. Historical
  schema-1 bundles retain their existing behavior.
- The project result shows the final criterion assessment, command outcomes,
  reviewed commit, local branch/worktree and link to the final run. A command that
  changes files is visibly incomplete. Added specific evidence/recovery exception
  messages. Live updates retain the existing form/disclosure behavior.
- Existing pinned Paperclip completion/recovery research from task 1056 informed
  criterion-bound completion; no third-party source copied and no dependencies added.
  `rtk proxy` remains limited to exact source reads and deterministic Python edits/
  structural checks, where output filtering would change required inspection data.

### Verification for this checkpoint

- Initial `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs test/cuckoding/walking_skeleton_test.exs test/cuckoding/execution/command_policy_test.exs`: 69 tests, five failures. They exposed command arrays being removed by the existing `argv` diagnostic redaction. Fixed the configuration/event representation without weakening the redactor.
- Focused final-flow checks also caught the runner's `{:ok, result}` return shape; corrected the boundary match. These failing runs were not acceptance evidence.
- `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs` passed: **39 tests, zero failures**, 51.3 seconds. Added real host subprocess coverage for final completion, a failing required command despite an optimistic Reviewer, automatic repair planning, missing criterion rejection, changed-head/forged-result/log-tamper rejection and command replay.
- `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs test/cuckoding/walking_skeleton_test.exs test/cuckoding/execution/command_policy_test.exs test/cuckoding/workflows/gate_evaluator_test.exs test/cuckoding/run_control_test.exs test/cuckoding/shared_authorization_migration_test.exs test/cuckoding_web/project_setup_live_test.exs test/cuckoding/project_onboarding_test.exs test/cuckoding_web/agent_settings_live_test.exs` passed: **100 tests, zero failures**, 66.8 seconds.
- After adding the explicit result branch/worktree presentation and extracting the command launch helper, `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs:349 test/cuckoding/board_control_test.exs:237` passed: **2 tests, zero failures**, 6.1 seconds. The Describe/Run/reconnect LiveView test now continues through Done and verifies the final result/check presentation.
- `rtk env -u CR_PAT mix compile --warnings-as-errors`, `rtk env -u CR_PAT mix format --check-formatted`, `rtk env -u CR_PAT mix credo --strict` and `rtk env -u CR_PAT mix sobelow --config` passed. Fixed clause grouping/complexity/nesting findings with small explicit helpers; no exemptions added.
- `rtk env -u CR_PAT mix assets.build` passed (Tailwind/esbuild); native bundle/build/runtime status remains unverified.
- `rtk git diff --check` passed. An inline `rtk proxy python3 -` check verified nine documents, 41 local link paths, balanced code fences and the unchanged staged adoption-plan blob `8ece06c315a8dbe530a4d6e22e23d84e773f58b9`. It did not validate heading anchors.

### Remaining work after this checkpoint — goal still active

1. AU-04: implement typed temporary-provider waits and productive continuation,
   separately bounded durable accounting/backoff, and actionable genuine exceptions.
   Existing timeout retries alone are insufficient. Investigate ACP max-token/turn
   stop reasons and existing `Types.Error` codes; do not classify raw provider prose.
   Resume must retain partial work and use compatible sessions or public evidence.
2. Finish complete AU-03/AU-05 capability, cumulative allowance and final repair
   acceptance, including command prerequisites for realistic empty/existing projects.
   A fixture `git diff --check` proves the host receipt mechanism, not a working app.
3. Run the complete relevant security/recovery regression set, full quality gates,
   and real-provider/native UI/sleep/restart acceptance. No full `mix quality`,
   authenticated provider demonstration, native build/install/restart, production
   migration or physical sleep evidence has been performed for task 1057.
4. The task and goal remain in progress. No commit, push, PR, merge or release was
   performed. The user's staged adoption proposal remains unchanged.

## Known-ended recovery checkpoint

Acceptance for this increment: a recognized temporary failure or exhausted
provider turn must preserve unfinished work and resume automatically, consume
separate durable finite counters, respect Pause/Stop/deadlines, and still pass
independent final review. Reconnect and repeated wakeups must not duplicate work.

- Reused existing stage checkpoints, board events, dispatcher and shared launch
  admission. `BoardControl.Recovery` records source attempt, cycle, scope, kind,
  consumed allowance and UTC eligibility before entering `waiting/goal_recovery`.
  Claim, run transition and resumed event are transactional. No extra queue,
  scheduler, migration or dependency was added for recovery.
- Transient failures use the existing per-task retry counter. Provider waits and
  continuations count append-only scheduled events per task or controller phase.
  Backoff is bounded (provider waits start at ten seconds; ordinary failures at
  one second; maximum five minutes), and the original goal deadline still applies.
  Provider-reported retry-after values are not currently available on this typed
  bridge boundary. A provider wait consumes its allowance even after restart.
- Same-run/worktree resume reuses validated completed-stage evidence instead of
  restarting the whole task. Code and prior review cycles remain intact. Failed
  stage durations use the normal timing command; duplicate timing cannot inflate
  totals. Process exit evidence now includes measured pause duration. Recovered
  attempts remain in cumulative time/usage while distinct continuation/wait limits
  avoid treating every productive turn as a failed review attempt.
- ACP max-token/max-turn stops retain their typed reasons. The pinned Claude
  bridge's terminal AIR metadata normalizes retryable rate/service failures without
  storing raw error titles/details. Quota/authentication/permission/unknown failures
  do not acquire automatic retry authority. Existing cancellation and permission
  errors take precedence over terminal stop metadata.
- Native continuation can reuse a known-ended failed session only after its
  productive continuation checkpoint is claimed. The remaining wall timer may
  narrow; account, model, role, runtime, workspace and other grant fields must
  match. Otherwise the existing bounded public-evidence continuation is used.
- Recovery refuses any process lacking an end record, cleanup failures, changed
  artifact hashes or invalid Git identity. Lost active prompt ownership remains
  an exception; the app does not blindly replay an ambiguous prompt.
- Project progress displays the wait/continuation type, consumed allowance and
  next eligible time without an alert. Pause/Stop remain available. Added specific
  deadline/cleanup/allowance explanations. Final command receipt replay can pass
  a dirty post-check worktree to the Reviewer without repeating commands; dirty
  work still cannot satisfy final completion, and protected paths are rechecked.

### Reference evidence

- Paperclip MIT source at pinned `a36cbffa9e71443a627641972052fbf52e636755`,
  `server/src/services/execution-recovery-attempt.ts:43–77`: separate failure,
  continuation and resource-wait accounting. Adapted the behavior to Cuckoding's
  existing attempts/board dispatcher; no source copied or company runtime added.
- Installed, pinned `@agentclientprotocol/claude-agent-acp` 0.81.2 (Apache-2.0):
  `dist/air-extension.js:1–60`, `dist/session-failure-extension.js:17–96,193–207`
  and `dist/acp-agent.js:2570–2610` define terminal typed failure metadata and the
  metadata-only capability. No bridge source was modified. Other adapters keep
  their existing capabilities. Files are under `agent_bridges/node_modules/`;
  package version remains fixed in `agent_bridges/package.json`.
- `rtk proxy` exceptions remain exact source reads and structured validation where
  filtering would alter the inspected data. No shell environment/argument dump,
  dependency installation or provider credential read was performed.

### Verification so far

- Initial recovery regression run: 99 tests, 56 failures. Normal calls passed nil
  into strict `and`; new terminal metadata overwrote existing cancellation errors.
  Fixed both shared boundaries. A following run had 104 tests, four failures:
  three new fixtures used the wrong runtime identity and one identity validator
  assumed a map where a negative test supplied a scalar. Corrected the fixtures
  and guarded nested identity handling. These were failing development runs.
- `rtk env -u CR_PAT mix test test/cuckoding/adapters/acp/client_test.exs test/cuckoding/board_control_test.exs:1242`: **37 tests, zero failures**.
- `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs:1291 test/cuckoding/board_control_test.exs:1320 test/cuckoding/board_control_test.exs:1344 test/cuckoding/board_control_test.exs:1370`: **4 tests, zero failures** (line selectors at that revision covered identity plus the three main recovery paths).
- `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs:1384`: **1 test, zero failures** for altered evidence/unverified cleanup.
- `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs test/cuckoding/adapters/acp/client_test.exs test/cuckoding/walking_skeleton_test.exs test/cuckoding/execution/local_process_runner_test.exs test/cuckoding/run_control_test.exs`: **128 tests, zero failures**, 110.2 seconds.
- Subsequent focused UI/timing/dirty-replay run: four tests, one fixture failure;
  the existing test board had not been linked as the project's delivery board.
  Fixed that fixture. `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs:1342`: **1 test, zero failures**, including rendered wait detail and Pause/Resume.
- `rtk env -u CR_PAT mix compile --warnings-as-errors`, `rtk env -u CR_PAT mix format --check-formatted`, `rtk env -u CR_PAT mix credo --strict` and `rtk git diff --check` passed. Credo findings were fixed with small helpers, no exemptions.
- The staged proposal remains blob `8ece06c315a8dbe530a4d6e22e23d84e773f58b9`.
- Full `rtk env -u CR_PAT mix quality` passed: **10 properties, 452 tests, zero
  failures**, 143.2 seconds for tests; formatter, unused dependency check,
  warnings-as-errors compilation, strict Credo, Sobelow and Hex advisory audit
  also passed. Expected fixture crashes in the plugin-supervisor test did not
  cause failures. These are current source/fixture gates, not provider acceptance.
- An inline `rtk proxy python3 -` structural check passed for nine documents,
  41 local link paths and balanced code fences; heading anchors were not evaluated.
- `rtk env -u CR_PAT mix assets.build` passed (Tailwind/esbuild). Final
  `rtk git diff --check` passed; generated assets did not add tracked changes.
- No real-provider/native or physical sleep gate is claimed by these fixtures.
  Task 1057 and the implementation goal remain active.

### Remaining acceptance

1. Finish structured, justified goal-changing questions and ordinary assumptions;
   current prompt guidance is not yet a host-validated question classification.
   After repeated task failure, allow a bounded independently reviewed change of
   approach before surfacing an exception. The current all-blocked path still
   stops at `next_decision_valid/1`; started blocked tasks cannot yet be replaced
   by `Plans.editable?/1`. Preserve their attempt/history/allowance provenance and
   legacy version-2 behavior when adding that version-3 repair path.
2. Verify complete cumulative/capability boundaries and final repair using realistic
   empty/existing project prerequisites; typed fixtures do not prove provider uptime.
3. Complete rendered/provider/native recovery evidence. Preserve
   all pending evidence as incomplete; no production migration, commit, release,
   app installation or restart has occurred in this increment.

## Justified questions, reviewed alternatives and real-provider acceptance

Acceptance for this increment: ordinary choices remain with the team; genuine
questions carry criterion/evidence context; exhausted classified task failures can
receive an independently reviewed alternative without resetting history or limits;
real planning and delivery exercise the same production boundaries in isolated data.

- Version-3 `ask` output now requires a closed requirement-choice/external-input
  explanation, a goal criterion, already-checked evidence and why guessing changes
  the outcome. Other actions require null question. Legacy contracts remain intact.
  The project page reuses the board question component/domain command and preserves
  entered answers across refresh; answers never grant execution capabilities.
- If only classified task failures remain, the existing revision loop can revise
  a known-ended stopped task's description. Task, criterion and dependency IDs,
  retry/continuation counts, prior attempts and unfinished worktrees are retained.
  No task becomes Ready until independent plan Review passes. Permission/unknown
  failures, questions, ambiguous cleanup and exhausted revision limits are excluded.
- Added a two-task integration regression using a real dependency-free Python
  unittest command: both tasks pass their independent fixture reviews, the second
  loses an earlier requirement, final host verification fails, and reviewed repair
  reaches Done under the original Run authorization and a new reviewed head.
  This is deterministic orchestration evidence, not a claim of live provider tests.
- Live planning revealed two output-contract problems. Command names were constrained
  by the host but not its schema/prompt; the schema now specifies lowercase snake_case
  up to 40 characters. A Reviewer copied an old nested proposal revision; schemas
  now bind current execution/revision/plan/head identity and the prompt explains the
  distinction. Host envelope validation remains strict.
- Live review correctly requested granular criteria, but the revised proposal left
  one unmapped. Version-3 host-invalid plans now reuse the existing rejected-plan
  history and three-proposal ceiling, returning host validation feedback without
  importing tasks. A corrected proposal still requires independent Review. The
  planner/reviewer instructions also clarify valid new-task dependency keys and
  remove contradictory pre-Run criteria instructions. No new correction queue.
- Browser checks exposed incorrect modal arguments in ProjectDeliveryLive. The
  shared component takes an event name and element ID, not a JS command and CSS
  selector. Fixed the call and added focused rendered cancellation coverage.

### Source verification

- Before the live contract fixes, `rtk env -u CR_PAT mix quality` passed:
  **10 properties, 455 tests, zero failures**, 146.8 seconds; formatter, unused
  dependencies, warnings-as-errors compilation, strict Credo, Sobelow and Hex
  advisory audit also passed. `rtk env -u CR_PAT mix assets.build` passed.
- `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs test/cuckoding/state_machine_test.exs test/cuckoding_web/board_live_test.exs`:
  **2 properties, 61 tests, zero failures**, 70.4 seconds before live contract fixes.
- `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs:342`:
  **1 test, zero failures** for the command-name schema at that revision.
- `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs:342 test/cuckoding/board_control_test.exs:367`:
  **2 tests, zero failures** for identity/schema validation at that revision.
- The first integration fixture used Node and failed with exit 126 before running
  tests: this machine's `node` is a Volta shim, unavailable under the run-owned HOME.
  A second diagnostic run confirmed that cause. Changed this orchestration fixture
  to a direct installed Python runtime and stdlib unittest, with ignored bytecode.
  The Volta issue is an open product prerequisite issue, not hidden by this change.
- `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs:294 test/cuckoding/board_control_test.exs:438 test/cuckoding/board_control_test.exs:466`:
  **3 tests, zero failures**, 8.5 seconds. Subsequent full board suite covers all
  four added schema/invalid-plan/integration checks regardless of line shifts.
- `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs`:
  **50 tests, zero failures**, 80.2 seconds, including the invalid-proposal ceiling.
- `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs:525`:
  **1 test, zero failures**, 4.4 seconds, including modal cancellation without Stop.
- `rtk env -u CR_PAT mix credo --strict` passed after the new plan correction path.
  A fresh full quality run is in progress after the modal correction.

### Live provider evidence so far — not yet a passing goal

Used a fresh SQLite database and fixture repositories under
`/tmp/cuckoding-1057-auth-check`, with endpoint/workers disabled except explicit
normal BoardControl dispatch. Existing dev/native databases were inspected only
read-only for saved account metadata. The harness refers to the existing app-owned
Codex authorization profile; it neither reads/copies credentials nor imports personal
provider profiles. Account metadata is copied only to isolated acceptance data.
No native bundle, production database, user project or running native app changed.

- `rtk env -u CR_PAT MIX_ENV=test mix run --no-start /tmp/cuckoding-1057-auth-probe.exs`
  passed live authorization and catalog checks. Evidence:
  `/tmp/cuckoding-1057-auth-check/authorization-result.json`.
  Selected catalog-supported `gpt-5.6-luna`, medium reasoning, for all three roles
  in separate sessions. The isolated team has 4 tasks, 2 revisions, 1 failure retry,
  2 continuations, 2 provider waits and a shared 15-minute deadline.
- First goal `01a0f3c5-44e8-7208-a869-78ecc0424045` stopped before Run: readable
  command labels violated the host name grammar. Second goal
  `01a0f3ca-3c2f-727e-81e0-242a80e32975` stopped before Run: valid review correction
  carried an old revision. Third goal `01a0f3cc-b44b-7dcc-89a8-6133d258522e`
  accepted the correction and replanned, then rejected missing criterion coverage.
  Each failure and worktree is retained; stopped through normal controls before
  starting the next fixture. Completed process records were verified. JSON result
  status, not the harness exit code, determines success.
- Current fourth run uses an explicit native Node tool path, without altering the
  user's global configuration:
  `rtk env -u CR_PAT PATH="/Users/mpak/.volta/tools/image/node/24.13.0/bin:$PATH" MIX_ENV=test mix run --no-start /tmp/cuckoding-1057-goal-smoke.exs`.
  Goal `01a0f3d1-79cc-7a8c-9148-f8cab85a4162` reached Ready to run, received one
  activation and progressed through first-task review into second-task delivery.
  Final result and the existing-project repeat remain pending at this checkpoint.
  Automatic support for version-manager shims is not established by this override.

### Browser evidence so far

`/tmp/cuckoding-1057-ui.exs` serves a SQLite backup on `127.0.0.1:4057` in safe
mode, with no execution workers. It uses a generated short-lived shell handshake;
secrets stay in mode-0600 temporary files and never enter reports. The normal
single-use browser-token exchange and unauthorized/token-replay rejection passed.
Playwright uses installed Google Chrome, because its bundled Chromium cache is
absent. The first interactive run failed modal focus restoration and led to the
source correction above; the corrected check is in progress. Preview assets are
source-built; this is not installed native-app evidence.

The original safe-mode preview could not use the normal shutdown policy against
copied active records (HTTP 500). After verifying PID/start time, executable file,
owned SQLite mapping, cwd and sole loopback listener, terminated only preview PID
51049 with SIGTERM and observed exit. Two preceding identity assertions correctly
refused to signal because macOS truncated `ps comm`; one attempted preview restart
failed with address-in-use and exited. The replacement preview uses a no-work
shutdown policy only because safe mode starts no execution workers. No other app
or provider process was stopped. Temporary browser scripts contain no credentials.

`rtk proxy` exceptions in this increment are exact source reads, structured file
edits/SQLite metadata checks, browser automation and identity-preserving process
inspection. XERJ peer search was attempted but its local node was unavailable;
existing project code supplied these workflow/modal mechanisms. No new dependencies
or copied peer code were added. Remaining gates include complete toolchain preflight,
final live/provider recovery, native/physical sleep acceptance and final docs checks.
Task 1057 and the goal remain active; no commit, push, PR, merge or release occurred.

### Verified empty-folder completion and rendered results

- Live empty-folder goal `01a0f3d1-79cc-7a8c-9148-f8cab85a4162` completed:
  two tasks, eight independently assessed criteria, zero questions and exactly one
  Run activation. Final head `bea0972d2a7d0f182de3732c36b3bacfbb08a138` is clean;
  final host `node --test` and `git diff --check` receipts both report exit 0.
  The initial repository base stayed `6b6366b6c39ce9fb79d85287a3cfe2a01b321fcd`;
  no owned process lacks an end record. Final controller run:
  `01a0f3d7-fb67-706a-839e-7f630b990303`. Evidence is in
  `/tmp/cuckoding-1057-auth-check/empty-v4-result.json` and the isolated event/artifact
  store. The same configured team created the existing-repository repeat without
  another login or role assignment; that repeat is still running.
- Fresh `rtk env -u CR_PAT mix quality` passed: **10 properties, 459 tests,
  zero failures**, 170.6 seconds; formatter, unused dependencies, compiler with
  warnings-as-errors, strict Credo, Sobelow and Hex advisory audit all passed.
- `rtk proxy /Users/mpak/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node /tmp/cuckoding-1057-ui.cjs`
  passed using installed Chrome: unauthenticated access and consumed-token replay
  rejected; Escape cancels Stop without executing it and returns focus; disclosure,
  unsaved brief and input focus survive live ticks; 1440px/390px views have no
  horizontal document overflow. Inspected desktop, narrow and narrow-controls
  screenshots. An initial full-page narrow screenshot repeated viewport paint;
  reran with viewport screenshots at top and controls, confirming one heading and
  readable controls. No UI source change was inferred from that capture artifact.
- `rtk proxy /Users/mpak/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node /tmp/cuckoding-1057-result-ui.cjs`
  passed against a fresh SQLite backup of the completed result: Done shows the
  reviewed commit, local branch/worktree, criteria and passing checks; 390px result
  wraps; final-run link resolves; the log endpoint returns 200 with the browser
  session and 401 without it. Inspected completed-result screenshots. Reports:
  `/tmp/cuckoding-1057-ui/browser-result.json` and `result-browser-result.json`.
- Visual inspection also found the new page showing raw legacy role keys. It now
  reuses `AgentFloor.role_label/2` from the immutable run snapshot. The focused
  project test passed again (one test, 4.9 seconds), asserting Reviewer display.
  `rtk env -u CR_PAT mix compile --warnings-as-errors` and
  `rtk env -u CR_PAT mix format --check-formatted` passed after that display fix.
- An inline `rtk proxy python3 -` check validated ten documents, 71 local link
  paths and balanced code fences; heading anchors were not evaluated.
  `rtk git diff --check` passed and the staged adoption plan still hashes to
  `8ece06c315a8dbe530a4d6e22e23d84e773f58b9`.
- Replacement isolated previews shut down through authenticated `/shell/shutdown`
  with HTTP 200 and exited cleanly. Neither native app nor real acceptance process
  was restarted. Existing-project live completion remains pending; real interrupted
  provider restart, physical sleep and signed native acceptance remain unverified.

### Existing-project completion and final checkpoint

The live harness finished with JSON status `passed`. Existing-project goal
`01a0f3d8-dda0-7a79-8567-d1b85a7f0bfc` reached Done at
`2b9cd6c9026d81e8a77283a5d89e05c69443600b`, retaining original base
`cf494308da0cafa73149554507eaaefd2be78500`. It has two tasks, eight passing final
criteria, passing `tests`/`integrity` host receipts, zero questions, and zero
processes lacking end records. Its original README heading remains exactly
`# Existing acceptance application`. Both successful fixtures used saved default
team **revision 1**; repeated identical setup calls were idempotent and did not
create revisions or require another account login/role assignment.

Sample: two successful live delivery starts, each with one Run activation and no
required subsequent input. Three earlier pre-Run failures are retained above;
this is not a 100% success-rate claim across all development attempts. Each final
goal has 12 provider-reported usage records and requested/actual model
`gpt-5.6-luna`. Empty: 73,995 input and 4,994 output tokens. Existing: 74,925 input
and 4,976 output tokens. Monetary cost is unavailable, not zero or estimated.
Evidence: `/tmp/cuckoding-1057-auth-check/goal-smoke-v4-result.json`,
`existing-v4-result.json` and `acceptance-summary.json`.

Independently inspected the empty project's generated CLI, tests and README:
exact greeting/newline, status-1 missing/blank validation, CLI subprocess tests
and usage documentation agree with the final evidence. This confirms a concrete
small CLI result; it does not prove framework bootstrap or every provider/toolchain.
All preview processes exited; port 4057 has no listener. No real acceptance process
remains running after the terminal harness result. Final `rtk git diff --check`
passed before this evidence-only append.

Remaining work, in priority order:

1. Close native-tool prerequisites before Ready. Current metadata lookup accepts
   Volta/asdf-style shims that depend on the user's real HOME, while the runner
   correctly retains an isolated HOME. The live Node proof used an explicit native
   binary PATH. Do not fix this by inheriting personal HOME/credentials or silently
   expanding grants. Preserve tool/version provenance and reject unresolved setup
   before Run; broader bootstrap acceptance remains incomplete.
2. Demonstrate live correction/recovery with a known transient interruption and
   durable restart. The full real delivery paths passed, and typed outage/
   continuation/correction fixtures passed, but this run did not force a post-Run
   live outage or physical sleep. Do not conflate those evidence classes.
3. Complete native/sleep and remaining capability/allowance acceptance. The new
   result UI, keyboard/input retention, authenticated logs and desktop/narrow
   layouts are verified in isolated source previews, not an installed signed build.
4. Keep AU-03–AU-05 and the goal open until the required work is handled or an
   explicit external acceptance handoff is agreed. No commit/push/merge/release,
   native install/restart or production migration has occurred.


### Native development-tool preflight

Acceptance for this increment: the saved team can plan and deliver using installed
native developer tools without an operator PATH workaround; missing/unusable tools
stop before Ready, changed tools cannot launch after Run, and personal HOME,
profiles, credentials and ambient environment remain excluded.

Implemented bounded metadata-only discovery for known installer layouts and a
small supported tool/companion list. This reuses the existing command validator,
supervised runner, process logs, events and immutable delivery authorization.
Plan review probes fixed version flags in the same restricted environment; Run
freezes native paths and size/mtime/inode records. Both agent children and host
checks derive PATH from those binary directories. No new dependency, registry,
credential store or setting was introduced. The UI's Run details show selected
paths. Historical authorizations retain their behavior.

Development findings and validation:

- An initial snapshot stored an `environment` field; the existing redactor
  correctly removed it, which exposed a Map.merge failure. Fixed the representation
  to retain only tool records and derive PATH. Redaction was not weakened.
- Strict Credo initially reported three nested-function findings. Extracted small
  existing operations; `rtk env -u CR_PAT mix credo --strict` then passed (238 files,
  4,651 modules/functions, no issues).
- A focused 19-test run found one assertion using `exit_status` instead of the
  process schema's `exit_code`. The actual exit-42 tool had ended and preparation
  had stopped correctly. Fixed that assertion.
- `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs test/cuckoding/execution/toolchain_test.exs test/cuckoding/execution/local_process_runner_test.exs test/cuckoding/reconciler_test.exs test/cuckoding/power/manager_test.exs`
  passed: **1 property, 82 tests, zero failures**, 87.5 seconds. Executed through
  an `rtk proxy python3 -` wrapper that removes test LiveView session/static
  attributes from failure output. Coverage includes native discovery without
  execution, missing companions, shim aliases, conflicting tool versions,
  isolated HOME/PATH, changed-tool launch rejection, owned cleanup and simulated
  sleep/reconciliation. This precedes the review-context adjustment below.
- Fresh live v5 preparation (`01a0f3f2-250f-7212-b44f-83775edb89b5`) found native
  Node and Git without a PATH override; both version probes exited 0. Reviewer
  then rejected absolute executables because its `available_tools` was empty,
  and the ACP client ended with `acp_session_lost` before storing a terminal
  result. Delivery never started. Preserved/stopped that attempt normally.
  Plan review now receives the same native catalog, and instructions distinguish
  the permitted executable path from forbidden absolute argument paths. Extended
  the existing regression to require catalog plus host tool evidence in Review.
- `/tmp/cuckoding-1057-restart.exs` is an isolated two-VM acceptance harness using
  the existing app-owned Codex account by reference. An initial temporary harness
  syntax error ran no application work; corrected the parenthesis. The fresh v6
  drill uses no PATH override and records only exception kind and stack MFAs on
  ACP process exit, never process arguments, environment, state or provider text.
  A temporary harness adapter injects one typed provider-unavailable outcome;
  production adapters and trusted configuration are unchanged. Its result is
  pending and must not be described as an actual upstream service outage.

Source formatting passed. `rtk proxy` exceptions here cover exact source reads,
structured edits, isolated SQLite metadata inspection and redacted test output.
No personal configuration or credential contents were read/copied. No production
migration, app restart/install, publication or Git integration was performed.


After the review-context fix, `rtk env -u CR_PAT mix quality` passed through the
redacting wrapper: **10 properties, 463 tests, zero failures**, 157.5 seconds;
formatter, unused dependencies, warnings-as-errors compiler, strict Credo,
Sobelow and Hex audit passed. Expected plugin-crash fixtures emitted two error
reports while their recovery tests passed. `rtk env -u CR_PAT mix assets.build`
and `rtk node --test test/task_board_motion_test.cjs` passed. Structural validation
passed for ten documents / 71 local link paths / balanced fences (anchors not
checked). `rtk git diff --check` passed. The staged proposal blob remains
`8ece06c315a8dbe530a4d6e22e23d84e773f58b9`.

Live v6 reached Ready and accepted one Run with native Node 24.13.0 and Homebrew
Git selected by the agent; both version probes passed with no operator PATH
override. The next controller session is still opening and has produced no
prompt-start event. Its owned guardian, bridge and Codex child are present;
only PID/parent/start/executable metadata and the empty redacted log were inspected.
The original deadline remains unchanged. Native bundle rebuilding is deferred
until that owned bridge exits, avoiding replacement of an in-use executable.


`rtk env -u CR_PAT MIX_ENV=prod mix release --overwrite` built the production
release successfully. The existing sterile verifier passed against that exact
release with a disposable database and app-owned HOME:
`rtk proxy env -u GEM_HOME -u GEM_PATH PATH=/usr/bin:/bin:/usr/sbin:/sbin CUCKODING_RELEASE_PATH=/Users/mpak/www/elixir/cuckoding.com/_build/prod/rel/cuckoding/bin/cuckoding /usr/bin/ruby desktop/verify.rb`.
It verified bridge hashes, migrations, loopback/authentication, one-use browser
handoff, redacted diagnostics, durable auth auditing, graceful cleanup, crash
cleanup, safe mode, durable update snapshot and rollback preserving the failed
candidate database. It started no provider work and changed no user database.
This is production-release smoke evidence, not an installed/signed app or physical
sleep/wake demonstration. All verifier-owned runtimes exited.


A separate no-auth, no-prompt startup diagnostic launched the native Codex binary
with a fresh temporary HOME/CODEX_HOME and only the JSON-RPC initialize request.
Both system PATH and the selected tool PATH returned the initialize response in
0.06 seconds. Each diagnostic process exited after stdin closed; no model work or
personal profile was used. This does not reproduce the live bridge/session stall
and is not evidence that its cause is fixed. The v6 deadline remains unchanged.


The v6 attempt did not pass. Its provider session remained before prompt start
until the unchanged 15-minute goal deadline. Normal control/runner paths then
cancelled the run, recorded a timed-out process and ended its guardian/bridge/
Codex child. PID/start/executable checks confirmed those owned processes exited.
The harness next raised `Exqlite.Error`; its bounded first-version diagnostic
retained only the exception class/top SQL frame, so the precise SQL reason is not
yet established. The board projection still read running while its current run
was cancelled. Do not claim successful autonomous settlement or restart recovery.
A fresh v7 harness now records only SQL-lock/begin booleans and stack MFAs, plus
ACP phase metadata. It also fixes the temporary harness to resolve agent roles
only. No production timeout, failure class or database policy was changed based
on this unresolved observation. A fresh unsigned native build was started only
after the owned bridge had exited.


`rtk env -u CR_PAT ./bin/dev.build` passed. It rebuilt the pinned bridges (three
hardening tests), production assets/release, release-metadata tests (7 runs / 20
assertions), restart helper tests (6 runs / 98 assertions), promotion checks,
native library bundling, Rust formatter, ten Rust tests and warnings-denied Clippy,
then created the development bundle and passed the sterile verifier again.
Artifact: `desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`.
No signing/notarization, installation, user-data migration, native application
launch or physical sleep was performed. The new v7 provider drill started after
the bridge build/rename step completed; its lifecycle monitor confirms prompting.


### Shared transport startup warning — root cause and regression

The v7 drill repeated the pre-prompt initialization stall until its original
15-minute deadline; owned processes ended, but lease release raised Exqlite.Error
and the board was not settled in that invocation. Its database integrity check
passed and no process row remained without ended_at. The diagnostic's comparison
against `database is locked` was false; that does not rule out Exqlite's distinct
`Database is busy` error. Do not treat the exact SQL cause as established.

Initialize-only probes narrowed the transport fault without sending model prompts:
native Codex, compiled bridge, and Ruby duplex shim responded under Python pipes,
including the exact saved config and app-owned account by reference. Erlang's
packet-4 port instead stalled with a prefixed native-tool PATH. Deduplicating env
keys did not help. Timestamp/byte-count-only tracing showed Ruby flushed valid
frames within 90 ms while Erlang delivered no packet. A raw-port probe identified
an unframed RubyGems `Insecure world writable dir` startup warning before the shim
ran; Erlang interpreted its initial bytes as a huge frame length. No protocol or
credential contents were printed or persisted by the probes.

The existing shim uses only Ruby stdlib. Added `--disable-gems` at its single shared
launcher, preventing automatic RubyGems startup before either shim. The exact ACP
initialize probe then returned in 141 ms. Extended the existing duplex/secret/
pause/ownership test with a temporary world-writable tool directory in PATH: it
failed on the old launcher (no response after 2 seconds), then passed with the
fix. `rtk env -u CR_PAT mix test test/cuckoding/execution/local_process_runner_test.exs test/cuckoding/adapters/acp/client_test.exs`
passed: **51 tests, zero failures**, 23.1 seconds.

Reference lookup: local launcher `local_process_runner.ex:730` and shim
`priv/runner/duplex.rb:1`; pinned Vibe Kanban
`crates/executors/src/executors/acp/harness.rs:200-252` keeps protocol stdout apart
from diagnostics. Its Apache-2.0 LICENSE was rechecked. No peer code was copied;
Cuckoding retains its existing framed transport, redaction and owned process groups.
The RTK proxy exceptions were exact source reads, temporary no-prompt probes and
SQLite metadata reads. No global permissions, Ruby installation, personal profile
or credential store was changed.

A separate harness defect was found: its Application.put_env replaced all Repo
settings, dropping our configured immediate transactions and 5-second busy timeout.
Exqlite then defaults to deferred transactions (deps/exqlite/lib/exqlite/connection.ex:608).
This is not evidence of a production lease-policy defect. The v8 prepare process
already started with that old harness configuration; its fresh resume will merge
the existing Repo options instead. No production database retry policy was changed.
The fresh v8 recovery drill uses the corrected transport with the original finite
limits and preserved earlier failures. It is still pending.


`rtk env -u CR_PAT MIX_ENV=test mix run --no-start /tmp/cuckoding-1057-restart-v8.exs prepare`
reached Ready without PATH overrides, accepted exactly one Run, finished the real
Speculator stage, then persisted the harness-injected typed provider wait before
exiting the VM. Execution `01a0f4ef-d9fb-74d8-a6d5-319217fa751d`, run
`01a0f4f1-8c28-738c-b066-20c3b52c6289`. The first development attempt is retained
as failed; specification is succeeded. The fresh `resume` invocation is now running
with the repository's immediate transaction / busy timeout settings preserved.
This is an injected adapter failure, not a measured upstream outage. The previous
15-minute deadline and immutable authorization are unchanged.


After the startup-warning fix, `rtk env -u CR_PAT mix quality` passed through the
redacting wrapper: **10 properties, 463 tests, zero failures**, 168.9 seconds.
Formatter, unused locks, warnings-as-errors compilation, strict Credo, Sobelow and
Hex audit passed; the expected plugin-crash fixtures passed their recovery checks.
The restarted v8 VM reused its saved run and completed its first task, then the
normal controller selected task two. Final integration is still pending.
Updated DEVELOPMENT's onboarding description and LONG_RUNNING_AND_POWER's narrow
known-ended autonomous recovery path to match the implemented flow. Physical
sleep/wake and installed-native acceptance remain explicitly separate.


### Real-provider recovery passed; physical acceptance remains open

`rtk env -u CR_PAT MIX_ENV=test mix run --no-start /tmp/cuckoding-1057-restart-v8.exs resume`
passed. The fresh VM used normal startup reconciliation and the shared board
controller with the unchanged original deadline. The real Codex run completed
both tasks, host `node --test` and `git diff --check`, and all five independently
assessed final criteria. Final reviewed head
`eb37be91ec94eb8fd4a9f86b38a5b188217392f6`; original repository base
`77b1688f5d0981c6061d068cea74bfd475b949bc` remained unchanged.

Evidence: `/tmp/cuckoding-1057-auth-check/restart-v8-checkpoint.json` and
`restart-v8-result.json`, with durable run/event history in the isolated
`acceptance.sqlite3`. Assertions confirmed the same run ID and worktree, one
completed Speculator stage on the interrupted task, exactly one provider-wait
recovery, immutable authorization, zero questions and zero unended owned process
records. SQLite integrity is `ok`, foreign-key check has zero rows. The board
history has one preparation authorization, one delivery authorization, two plan
proposals/reviews (automatic correction), two completed tasks and one final goal
assessment. Native Node/Git preflight and delivery used no manual PATH override.
The saved team was reused; the model remained gpt-5.6-luna with medium reasoning.

This is one additional successful empty-project sample, with a harness-injected
typed failure and real-provider execution before/after the VM restart. It is not
an actual upstream outage, forced test-regression run, physical sleep/wake test or
installed-app demonstration. Final integration regression/repair remains covered
by the deterministic two-task fixture; earlier empty and existing real runs are
recorded above. No comparative reliability/cost claim follows from these samples.

AU-01–AU-05 implementation checkboxes now reflect source, fixture and real-provider
behavior; the task remains in progress for the explicitly separate physical/native
acceptance gate. Current-source native rebuilding started only after all owned
provider processes ended. No production database or user's running app was changed.


Current-source `rtk env -u CR_PAT ./bin/dev.build` passed again, including bridge
hardening (3 tests), metadata (7 runs/20 assertions), restart helper (6 runs/98
assertions), promotion, Rust (10 tests), formatter/Clippy, native bundling and all
sterile update/rollback checks. The app's LocalProcessWorker BEAM is byte-identical
to the production release: SHA-256
`7dd3b3e1f670753286edaed7358a07dd59f46da464b39bd21cb3aaacf3d0c0e0`.
No installation, signing, notarization or user's app restart occurred.

The final existing-project repeat now runs the exact bundled control plane at
`desktop/src-tauri/target/release/bundle/macos/Cuckoding.app/Contents/Resources/release/bin/cuckoding`
via `eval Code.eval_file("/tmp/cuckoding-1057-native-v9.exs")`. It uses sterile host
PATH/HOME, a generated private bootstrap file, the isolated acceptance database,
app-owned authorization by reference and the existing default-team revision 1
without re-saving it. Host-only CUCKODING_RUNTIME_HOME permits metadata discovery;
it is not passed to agent environments. PHX_SERVER is false. Normal production
worker/power settings are retained, and the harness no longer calls dispatch_once:
only the application's dispatcher advances work. This closes the earlier sample's
manual PATH limitation and tests the packaged release; it does not launch the
Tauri shell or exercise physical sleep. The result is pending.


### Actual Codex capacity failure exposed a missing metadata negotiation

The packaged v9 sample stopped before Run, during plan review. Recorded public
output said the selected model was at capacity, but the host received end_turn
without structured task output and classified `acp_invalid_structured_output`.
The process exited cleanly. This sample failed and is not counted as completion.
No textual error matching or silent model fallback was added.

Inspected the pinned Apache-2.0 Codex bridge 1.13.1 source and license:
`agent_bridges/node_modules/@agentclientprotocol/codex-acp/dist/index.js:29714`
maps server overload to service/retry; `:29754` maps native error codes; `:29840`
returns terminal AIR failure metadata only when negotiated; `:37636` checks the
capability and `:37763` advertises it. Cuckoding requested that exact read-only
sessionFailure capability only from Claude. Both pinned bridges already implement
it, so the minimal shared-client change enables the same strict terminal metadata
handling for Codex. It grants no tools and retains quota/auth/permission exceptions.
No upstream patch, dependency, text heuristic or new recovery engine was needed.

Extended the existing rate/overload/quota regression across both adapters.
`rtk env -u CR_PAT mix test test/cuckoding/adapters/acp/client_test.exs:101`
failed the three new Codex cases before the fix while the three Claude cases
passed. Assertions also require the advertised metadata capability, owned process
cleanup and absence of private error details. Focused checks are running after
formatting; the final bundle must be rebuilt with this additional adapter fix.


After enabling Codex metadata negotiation,
`rtk env -u CR_PAT mix test test/cuckoding/adapters/acp/client_test.exs test/cuckoding/execution/local_process_runner_test.exs`
passed: **54 tests, zero failures**, 23.8 seconds. Full quality and a fresh native
build are running. The existing-project v9 retry will use the normal domain Retry
before Run, preserving the initial failure and original deadline; it will not
reset the saved goal allowance or claim the initial capacity interruption recovered
automatically on the older client. The initial failed harness result is retained
as `goal-smoke-native-v9-initial-result.json`.

The successful v8 recovery sample recorded 14 usage facts: 88,614 input tokens and
6,788 output tokens; monetary cost remains unavailable. These are recorded provider
facts for that sample, not a benchmark or a claim about optimization savings.


The rebuilt native bundle passed `rtk env -u CR_PAT ./bin/dev.build` with all
sterile verifier gates again. Its ACP Client BEAM matches the production release,
SHA-256 `4c99a690a92f83483ab4046552d217b99e81e1ff6fb2cde3588bd734d43cda8b`;
the LocalProcessWorker digest is unchanged from the previous verified bundle.
The existing v9 execution is now being retried before Run through the domain
control using `/tmp/cuckoding-1057-native-v9-retry.exs`, loaded by that packaged
release. It retains the original 01:01:07.588719 UTC start and 15-minute deadline,
its original project/base and the initial failure record. No provider/model/team
setting or consumed allowance was changed. This explicit pre-Run development retry
will be reported separately from required human actions after Run.


Full quality after the Codex metadata change passed: **10 properties, 466 tests,
zero failures**, 171.0 seconds, plus formatter/compiler/Credo/Sobelow/Hex audit.
The packaged pre-Run retry then reached Ready and accepted one Run. It next
stopped on a separate host validation failure: controller output selected Task 2
while its Task 1 dependency was pending. The host rejected it with
`invalid_controller_output`; no delivery task ran. The report/history are retained.
This current-source existing-project sample still has not passed.

The response schema allowed arbitrary task IDs even though the host validator
required next_task_id. It now restricts IDs to the next eligible task, blocked
recovery candidates and null. Prepared-goal decisions also validate inside the
read-only stage, before it succeeds: invalid decisions retain their artifact and
use the existing known-ended recovery/checkpoint path under a specific
`invalid_goal_decision` code and the saved failure-retry ceiling. The next turn
gets bounded host recovery metadata and explicit correction instructions. Commit
validation still rechecks current state/authority; no stale authority, action or
dependency is bypassed. Fixed-batch behavior is unchanged. Added focused cases
for automatic correction without task launch and exhaustion without unlimited
retries. The full board test file is running; no additional engine or dependency
was introduced. Native rebuild/fresh existing-project evidence must follow.


The board suite initially passed both new correction/ceiling regressions but
failed its partial-input schema test: `members` was absent. Treating absent
members as an empty list safely leaves only null/next-task choices. Full quality
is rerunning after that correction. The current `rtk env -u CR_PAT ./bin/dev.build`
passed again, including all sterile verifier gates. A fresh packaged existing-
project v10 goal now runs with both fixes, normal production dispatch and the same
saved team revision 1. The v9 failed execution is stopped through its normal
confirmed control while retaining records. v10 is a separate explicit acceptance
sample with its own finite 15-minute authorization; v9's allowance/history was not
reset. Its harness is `/tmp/cuckoding-1057-native-v10.exs`.


Current-source `rtk env -u CR_PAT mix quality` passed through the redacting wrapper:
**10 properties, 468 tests, zero failures**, 176.7 seconds. Formatter, unused locks,
warnings-as-errors compiler, strict Credo, Sobelow and dependency audit also pass.
Structural documentation checks pass for 16 files, 115 local link paths and balanced
fences (anchors not checked); `rtk git diff --check` passes. The packaged v10
execution `01a0f509-a7a2-7a0f-91fe-34cefb764dd0` reached Ready, accepted one Run and
entered delivery under the normal production dispatcher. Final completion remains
pending; the existing failed samples are retained separately.


The real packaged v10 first task entered a review correction after Run: the first
QA attempt completed, then the executor automatically ran a second Speculator
stage and began a second Implementor stage in the same task run
`01a0f50a-ac0e-78c0-b986-6792f13bcccf`. This is live post-Run correction evidence,
not a harness-injected review failure. Completion and final criteria remain pending.
No questions, additional Run action, grant change or deadline extension occurred.


### Final current-build packaged result — passed

The normal production dispatcher completed v10, execution
`01a0f509-a7a2-7a0f-91fe-34cefb764dd0`. One Run delivered two reviewed tasks through
one real post-Run correction (two Speculator/Implementor/Reviewer cycles on task
one), with zero questions or operator controls after Run. Final host `node --test`
and `git diff --check` both exited 0; **all seven final criteria passed**. The
final reviewed head is `0c46725858da70099dc02d0dce4d5984e2a0dc89`; the original
repository base `c560bc426e8799a3c05847883b8ea648255d73ce` and existing README
heading were preserved. Default-team revision 1 and the delivery authorization
remained unchanged. This sample required no manual PATH override, account setup,
role reassignment or manual dispatch.

Evidence: `/tmp/cuckoding-1057-auth-check/existing-native-v10-result.json`,
`goal-smoke-native-v10-result.json`, `native-v10-module-hashes.json` and the durable
isolated database. Fifteen usage records total 86,636 input / 7,193 output tokens;
monetary cost is unavailable. SQLite integrity is `ok`, foreign-key check is
empty, no process row remains unended, and none of the sample's 19 recorded PIDs
is present. Packaged release evaluation exited 0 and deleted its private bootstrap
file. The one non-JSON diagnostic line was withheld; no raw secret/session output
was printed. All verifier/provider test processes have completed.

Final implementation evidence is 468 tests / 10 properties plus compiler,
formatter, static/security/dependency checks; current development bundle with
sterile migration/auth/cleanup/update/rollback checks; earlier authenticated UI
checks; real empty-project restart recovery with an injected provider wait; and
this current packaged existing-project delivery with a natural Review correction.
Artificial final-integration regression/repair is covered by the focused fixture,
not claimed as a forced live-provider demonstration. Failed v5–v9 samples remain
retained and are not counted as successes. No broad provider reliability or cost
comparison is claimed.

The outstanding device/release boundary is explicit: no physical sleep/wake,
installed Tauri-shell run/restart, signing/notarization or clean-machine install
has been performed for this build. The user's running app/data were not migrated
or restarted. The next device test requires an operator decision because sleeping
the Mac interrupts other work; a native data upgrade must first follow the backup,
integrity and owned-instance procedure in docs/DEVELOPMENT.md. Task 1057 remains
in progress at that acceptance boundary. No commit, main integration, push, PR,
merge or publication occurred. The staged proposal remains unchanged.

### Device acceptance boundary revalidated — 2026-10-01 01:34 UTC

The preceding goal turn made implementation and acceptance progress, then asked
for permission to run the disruptive device check. This automatic continuation
contains no answer to that request. Read-only revalidation found no currently
running Cuckoding executable, so there is no live test handle to wait for. The
native shell derives its normal application data directory; no disposable-data
override is provided by the documented native launch procedure. The device test
remains pending, and no app launch, user-data migration or physical sleep occurred.

`rtk proxy python3` metadata/evidence probes confirmed that all six packaged BEAM
hashes still match the v10 manifest, the isolated acceptance database returns
`integrity_check = ok` with zero foreign-key violations, and the v8/v10 result
files retain their passing outcomes. The staged proposal blob remains
`8ece06c315a8dbe530a4d6e22e23d84e773f58b9`; the branch remains
`feature/1057-autonomous-project-flow`. No implementation files changed, so the
already-passing test/build gates were not repeated. Proxy exceptions in this
continuation were exact document/evidence reads and process metadata inspection
using PID/start identity, executable, working directory and listeners only.
No raw process arguments or environments were inspected.

### Approved native device acceptance — October 1, 2026 (America/Chicago)

The user explicitly approved the device test. The native application was stopped
with no database holders. Preflight found two projects, 17 tasks, five runs
(three blocked, one done, one queued), and no running/waiting/hibernated run.
The six packaged module hashes still matched the verified v10 manifest.

Created and independently verified the mode-0600 SQLite online backup at
`/Users/mpak/Library/Application Support/com.cuckoding.desktop/manual-backups/1057-device-20261002T042314Z/cuckoding.sqlite3`.
Its SHA-256 is
`e6fe45492cdd703ee4bd09d47090bff1007760cc2f9143a7d8a5703862ed039e`.
No project knowledge/configuration files existed at the documented snapshot paths.
The private manifest and migration-result.json remain alongside the backup.

`rtk proxy python3` invoked the exact bundled release's Ecto forward migrator,
first on a copy of the backup and only after success on the idle native database.
Exactly versions 20260928120000, 20260930120000 and 20260930130000 were applied.
Both passes returned integrity `ok`, zero foreign-key violations, and identical
hashes of all original column values in every row across 45 pre-existing data
tables. The migration-history table gained only the expected versions. Temporary
private bootstrap credentials were removed; no pending-update marker was created.

`rtk ./bin/dev.restart` started the existing verified bundle successfully:
shell PID 83030, bundled BEAM PID 83072, loopback listener 127.0.0.1:57542,
health `ok` (identities observed at 2026-10-02 04:24 UTC). This is a native Tauri
launch, not the earlier backend-only eval. No install/sign/notarization occurred.
The helper emitted the known host PATH/Ruby warning; no framed protocol was used
by that helper and launch succeeded.

The authenticated Chrome dashboard was opened through the native handoff. CUA
could not bind the tray-only app and later recovered from a browser-control pipe
failure without replaying actions. A separate existing-project planning run
appeared after launch and reached task-proposal review; it was not started,
changed or counted as this acceptance sample. Default-team revision 1 was saved
through Agents using the already-connected Codex-Luna-High-5.6 for all three
independent roles with the displayed finite default limits. Existing assignments
and provider credentials were not changed by this test.

Created the empty test folder
`/private/tmp/cuckoding-1057-device-20261002/empty-project` and reached the native
folder chooser in the new-project wizard. The script-owned chooser is inaccessible
to CUA; requested the user's selection of that folder. Physical sleep has not yet
been triggered. Noninteractive sudo cannot schedule an automatic wake, so the
approved sleep check will require a manual wake. No power settings or existing
wake schedules were changed. Proxy exceptions were exact source/metadata reads,
private backup/migration operations and redacted health/power preflight. All shell
entrypoints were prefixed with RTK; subprocess diagnostics were retained privately
or summarized without raw credentials, process arguments or environments.

### Wake metadata crash found before the physical drill

The new-project form returned to step 1 before native folder selection completed;
no acceptance project was created and no owned chooser process remained. No
corresponding LiveView error was found in the inspected diagnostic window, so this
is not attributed to a product crash. The browser/task flow needs to be resumed.

The diagnostic review did expose retained Power.Manager `Protocol.UndefinedError`
failures. Current source confirms the same root cause: `Leases.expire/1`
(`lib/cuckoding/execution/leases.ex:105`) returns an integer count and
`Reconciler.finish_reconciliation/5` returns that count as `expired_leases`, while
`Power.Manager.reconciliation_metadata/1` attempted to enumerate it as lease rows.
The existing power-test doubles incorrectly returned lists. All callers and
metadata consumers were searched; only the power manager had the mismatch.
The existing Cuckoding lease/reconciler contract is the reference for this fix;
no upstream code, dependency or new recovery mechanism was needed. Ponytail 4.10.0
(MIT), local-runner, security-review, Phoenix and quality-gates remain applied.

The real-reconciler regression and corrected doubles reproduced the failure:
`rtk env -u CR_PAT mix test test/cuckoding/power/manager_test.exs` returned five tests,
three failures, all at the count-to-enumeration conversion. The one-line fix
records the real integer as `expired_leases` rather than inventing lease IDs.
No historical event is rewritten. After formatter,
`rtk env -u CR_PAT mix test test/cuckoding/power/manager_test.exs test/cuckoding/reconciler_test.exs`
passed **14 tests and one property**, zero failures. The new regression invokes
the real reconciler, requires the manager to stay alive, and verifies the durable
successful wake event and numeric counts.

Before rebuilding, verified zero active provider sessions and zero unended
process rows. Reused DeveloperRestart's exact ownership/descendant checks and
supported TERM shutdown path; all four observed native descendants exited
gracefully. No force kill occurred. Full quality and native build are running
through an RTK-prefixed private-log wrapper in
`/tmp/cuckoding-1057-device-20261002/`; no physical sleep has occurred yet.

Full `rtk env -u CR_PAT mix quality` passed: **469 tests, 10 properties, zero
failures**, 186.0 seconds, with formatter, unused locks, warnings-as-errors
compiler, strict Credo, Sobelow and dependency audit. Current-source
`rtk env -u CR_PAT ./bin/dev.build` passed in 79.8 seconds, including native
packaging and all sterile verifier gates. Private logs are `quality.log` and
`build.log` beneath the device-test directory. No implementation edits followed
those gates.

`rtk ./bin/dev.restart` launched the fixed bundle successfully on
127.0.0.1:58779; shell PID 6904 and bundled BEAM PID 7106 were verified by executable,
parent and start identity at 2026-10-02 04:42 UTC. The new Power.Manager BEAM
SHA-256 is `f09518800f624eb8568030bc3f188311bff63cd70f798fdfdc17327558f60119`;
eight module hashes are saved in `bundle-module-hashes.json`. Native health is
`ok`; database integrity remains `ok`, foreign-key violations remain zero, and
no owned process row is unended. The separate planning run is now hibernated by
the approved graceful shutdown, with history retained. This is evidence of native
launch/hibernate/relaunch, not yet autonomous delivery across restart or sleep.

The user's previously requested folder selection is superseded by the rebuilt
native app. Requested opening the new authenticated dashboard and registering the
named empty test folder, leaving its brief blank for automated continuation.
This is an automation-access limitation of the tray menu and script-owned folder
chooser; device-test approval is already granted and is not being requested again.
The physical sleep test and complete autonomous native recovery remain pending.

### Native empty-project acceptance resumed

The user completed registration of `Native recovery acceptance 1057` at
`/private/tmp/cuckoding-1057-device-20261002/empty-project`, project
`01a0faf1-7b71-7119-af4f-c523a3f940f6`. The native dashboard confirmed that it
inherited the saved default team. Through CUA, submitted the same dependency-free
two-task Node greeting/error-handling brief used by the earlier acceptance sample.
Execution `01a0faf6-c98e-7db1-8aec-85b4232b019f` entered read-only planning at
2026-10-02 04:54 UTC; independent plan review returned a correction and normal
dispatcher preparation continued without manual task edits. No Run has yet been
pressed at this checkpoint. Native provider requests use the selected
`gpt-5.6-luna` account; no credentials or account grants were changed.

CUA tab switching required a fresh accessibility snapshot immediately before the
action while another browser tab was changing. The form was submitted once.
Read-only SQLite probes use the actual table/column schema (two initial diagnostic
queries used incorrect names and were corrected; no write occurred). The private
read-only `/tmp/cuckoding-1057-device-20261002/probe.py` captures execution/stage/
process identities, authorization hash and power events for before/after evidence.
RTK proxy exceptions are exact metadata/source reads and this structured probe.

### Physical sleep/wake exercised on the native delivery run

The corrected plan reached Ready with exactly two sequential tasks and nine
criteria. The native command preview showed only the verified Node executable
with `--test` and `/usr/bin/git diff --check`. Pressed Run once at
2026-10-02 04:58:35 UTC. The frozen authorization hash is
`8c6ed2c2addb844d3ccb62713ab5a31976b6fb1221b0daee2a324a43cb9497d7`.

After a heads-up to wake the Mac manually, an RTK-prefixed private Python wrapper
verified a live acceptance provider stage and invoked `/usr/bin/pmset sleepnow`
at 04:58:57 UTC; exit 0, `Sleeping now...`. This was real physical sleep. The
sleeping stage was task run `01a0fafa-b1e5-7f41-952d-0b2ce561d935`, specification
attempt `01a0fafa-b3e0-7361-b9ef-95bdb0113650`, owned process PID 19599 with its
recorded start identity. System `pmset -g log` timestamps independently confirm
Sleep/Wake/DarkWake cycles; only timestamps and event kinds were emitted. The
first diagnostic decode encountered an invalid UTF-8 byte; the read-only parser
was rerun with replacement decoding, without exposing raw system logs.

macOS cycled through background wakes. At 05:10 UTC, the native manager had
recorded 12 measured gaps totaling **202,608 ms**, each with a corresponding
successful `wake_reconciled` row and run resume event. All reconciliation counts
were numeric; the earlier Power.Manager exception did not recur. Both native
shell and BEAM retained their original PID/start identities, health remained
`ok`, database integrity was `ok`, and foreign-key violations were zero.
The original Run authorization was unchanged and exactly one authorization event
existed. The same specification attempt succeeded and advanced to Implementor.

To end repeated background sleeps, after reading the installed `caffeinate`
manual, ran `rtk proxy /usr/bin/caffeinate -u -t 5`; it exited 0 and its temporary
user-active assertion expired. No saved power settings or wake schedules changed.
CUA then reported the Mac locked and required manual unlock; requested that action
without requesting device-test permission again. The application continued in the
background. Implementor was silent from approximately 05:01:59 until 05:10:06,
then succeeded and advanced to independent Review without intervention, retry,
restart or authority change. This delay is retained as observed behavior; no
unverified cause or typed automatic recovery is claimed.

Private evidence is in `before-sleep.json`, `sleep-request.json`,
`system-power-events.json`, `physical-checkpoint.json` and
`physical-checkpoint-summary.json` under the device-test directory. This checkpoint
proves physical wake reconciliation and single execution through specification
and implementation; final delivery, UI result and native restart acceptance are
not yet complete. RTK proxy exceptions were structured read-only evidence probes,
process executable/PID/start/state metadata and the documented power commands.

### Native physical drill completed — 2026-10-02 05:19 UTC

The normal production dispatcher finished the complete native empty-project goal
at 05:19:19.286051 UTC: **one Run, two tasks, nine passing final criteria, two
passing host checks, zero task questions and zero manual recovery controls**.
The independent final review accepted clean head
`bf02486aa8a916b9301cb114b9e8bde9eaafea34`; task 2 began from task 1's reviewed
commit `c6b8faa2ea198ee077d55e3a8b6f86b17d905239`. The original checkout remained
clean at `4077aff0f1a82f532233729299c23de90f971c78`. The original authorization hash
remained unchanged throughout all 12 physical sleep gaps and completion.
Each task's specification, implementation and Review ran once. The ordinary
plan-review correction occurred before Run and completed automatically.

Final review run `01a0fb0c-5a65-77aa-b7b9-d42d665a4951` retained successful
`node --test` and `git diff --check` host receipts. An RTK-prefixed structured
Python verification checked both artifact SHA-256 values, the clean final Git
head, and three direct executions of the generated `greet.mjs` with the verified
Node 24.13.0 executable and a restricted environment: valid name returned exact
greeting/exit 0, missing name and whitespace-only name returned exact error/exit 1.
All assertions passed; evidence is `result-cli-checks.json`. This result check did
not change the candidate or re-run planning/delivery.

At 05:21 UTC, `native-final-result.json` and `native-final-snapshot.json` recorded
all 20 owned process rows ended and no OS process with a matching recorded
PID/start identity. Native health remained `ok`; SQLite integrity remained `ok`
and foreign-key violations zero. Fourteen provider usage facts report 107,740
input tokens and 13,086 output tokens. Provider cost was unavailable, not zero;
no price estimate or comparative Paperclip improvement is claimed. The long
Implementor silence is retained as observed latency, not described as proven
transport recovery. No source files changed after the 469-test/10-property
quality gate and native build; this continuation changed evidence documentation.

CUA's last observation requires manual Mac unlock, so final native result-screen
inspection remains pending. The app and completed result are left intact at the
current loopback listener 127.0.0.1:58779. This is passing native physical sleep
reconciliation and complete autonomous delivery; it does not claim an in-flight
Tauri-shell restart or signed/clean-machine release. Those gates remain explicit
in task 1057. No commit, main integration, push, PR, merge or installation occurred.
The staged adoption-plan blob remains
`8ece06c315a8dbe530a4d6e22e23d84e773f58b9`.

Final documentation gates: `rtk git diff --check` passed. The RTK-prefixed
Python structural check covered four changed documents, 15 local Markdown link
paths and balanced code fences, with zero failures.
`rtk git rev-parse :docs/PAPERCLIP_ADOPTION_PLAN.md` confirmed the unchanged staged
proposal blob above. No implementation changes required repeating the already
passing formatter/compiler/static/test/build gates.

### Continuation audit — October 2, 2026, afternoon (America/Chicago)

The prior device turn made concrete progress: native physical sleep and complete
autonomous delivery passed. The later in-app-browser attempt supplied a concrete
client rejection (`ERR_BLOCKED_BY_CLIENT`), not evidence of a product test failure.
This continuation revalidated the running checkout-owned shell PID 6904 and BEAM
PID 7106 by executable, parent and start identity; their loopback health remains
`ok`. All eight bundle module SHA-256 values match the recorded device-test
manifest. The durable completed execution, final head, single authorization,
nine criteria and retained evidence still match `native-final-result.json`;
current SQLite integrity is `ok` with zero foreign-key violations. No new source
changes or repeat product-test claims are made.

The Mac is now unlocked. Native Chrome showed the acceptance project, but it now
has another preparation, execution `01a0fdb4-655c-7889-9461-15b2839a9668`, created
at 12:40:53 CDT (17:40:53 UTC). Read-only inspection confirmed the original
`01a0faf6-c98e-7db1-8aec-85b4232b019f` remains Done. The new preparation was not
started, modified or stopped by this continuation. Following the observed
Inspect tasks and evidence link returned `/unauthorized`; the previously open
LiveView is not proof of a current authenticated navigation session. Requested
a fresh normal tray-menu handoff. No cookie extraction, token minting, direct
database write or authentication bypass was attempted.

The native tool has no directly usable tray-only app target, and the in-app
browser connection cannot open the loopback URL. The remaining UI action is
therefore an operator handoff, not another request for device-test permission.
The accepted known-ended fresh-VM restart sample and passing native sleep sample
do not prove in-flight Tauri restart. That gate and the separately authorized
signed/clean-machine release gate remain incomplete. No completion is claimed.

Continued with the repository quality/menubar/security rules and refreshed the
upstream Ponytail skill to **4.10.1, MIT, full mode**. RTK proxy exceptions were
exact source/evidence reads and structured read-only process/database/hash probes.
Documentation-only updates replace the stale unlock blocker with the observed
expired browser-session blocker; all implementation and staged proposal changes
remain as before.

Continuation verification: `rtk git diff --check` passed; the RTK-prefixed Python
link/fence check passed for three updated documents and 13 local links.
`rtk git rev-parse :docs/PAPERCLIP_ADOPTION_PLAN.md` again returned
`8ece06c315a8dbe530a4d6e22e23d84e773f58b9`. A final native browser observation
still displayed `/unauthorized`, so authenticated UI acceptance remains pending.

### Native restart at the completed/Ready boundary

The next continuation found the newer preparation at Ready, no running runs and
no unended process records. The normal browser session is still not refreshed.
Device-test authorization remains in force. Before invoking the documented
`rtk ./bin/dev.restart`, captured both the successful physical-drill execution
and newer Ready execution, their immutable payload hashes and run counts in
`native-restart-before.json`. Acceptance for this narrow lifecycle check is:
graceful owned shutdown, exactly one healthy relaunch, unchanged completed result
and Ready plan/authorization facts, no new run, and intact SQLite. This is a
pre-Run retention check, not a substitute for in-flight autonomous restart.

`rtk ./bin/dev.restart` passed at approximately 12:50 CDT. It gracefully stopped
the verified shell PID 6904 and its descendants and launched exactly one new
shell/release pair: shell PID 22370, BEAM PID 22414, both starting October 2
12:50:08 local time, listener **127.0.0.1:63382**, health `ok`. The known Ruby
warning about the host PATH appeared in the developer helper; no protocol
framing or new application error was involved. The prior listener 58779 is now
historical and must not be used as the current app address.

`native-restart-result.json` confirms the captured completed/Ready execution rows
match exactly: state, phase, revision, base/head, current-run/task references,
preparation hash, frozen snapshot hash and delivery-authorization hash. Run counts
are unchanged; no provider/delivery process was admitted. All prior owned native
PIDs are gone; current unended process records are zero. SQLite integrity is `ok`,
foreign-key violations zero. The result and Ready-plan retention gate passed.
This changes the native lifecycle evidence, but does not claim recovery while a
provider prompt is active.

The only normal browser session still visible before restart was expired. The
previously requested tray-menu handoff remains necessary and now opens the new
listener; no repeated permission request or authentication bypass was introduced.
Ponytail 4.10.1/MIT/full and quality/menubar/security instructions remain applied.
RTK proxy exceptions were exact read-only SQLite/process/HTTP metadata probes and
private JSON evidence writes. No source, migration, saved team or execution grant
changed; no code tests or native build were repeated without a source change.

Documentation verification for this restart entry passed: `rtk git diff --check`;
the RTK-prefixed Python link/fence check (three documents, 13 local links, no
missing paths or unbalanced fences); and the staged proposal hash check, still
`8ece06c315a8dbe530a4d6e22e23d84e773f58b9`.

### Blocked audit after the native restart check

The previous goal turn was progress: the supported completed/Ready native restart
ran and passed its declared retention checks. This continuation is not a verified
wait: SQLite reports zero running runs and zero unended process records; the
newer execution is still waiting at Ready, and the physical-drill execution is
still Done. The current listener 127.0.0.1:63382 remains healthy.

Revalidated the browser against that current listener, not the historical port:
navigating the existing Cuckoding tab to the test project returned
`http://127.0.0.1:63382/unauthorized`. The earlier tray-menu handoff request has no
answer and no fresh authenticated session is available to CUA. The same normal
shell-to-browser authentication boundary has persisted through three consecutive
resumed goal turns, while all independent acceptance work available in those
turns was completed. No further restart, artificial activity, token/cookie
extraction or authentication bypass is justified.

The blocked audit threshold is now satisfied. Completion remains unproven:
final native result UI, recovery during active native delivery, and separate
signed/clean-machine release acceptance remain open. The next operator action is
to open Cuckoding from its tray menu and make the authenticated dashboard available.
No device-test permission is being requested again. The full implementation goal
and every remaining gate are retained; this is a block, not completion or a
redefinition of scope.

Verification used RTK-prefixed read-only SQLite/health probes and native CUA.
The staged proposal and implementation are unchanged. Only this explicit handoff
was appended to the worklog; `rtk git diff --check` is the proportional final gate.

### Guided front door and result screen — 2026-10-02 evening

The home project card now leads with Describe and run. Board creation, project
settings, and existing boards sit under Advanced controls. The project screen
uses the existing pearl panels and shows recorded plan assumptions, the final
commit, branch, worktree, a loopback preview when one exists, and Finder/editor
actions through the existing worktree opener. Publishing stays a separate
approval. Needs you copy states that an answer changes the outcome and does not
grant a capability. PRODUCT, FLOW, SECURITY, UI_DASHBOARD, and the adoption-plan
status now describe this as the working-tree front door. In-flight native
restart and a signed release remain open.

- `rtk env -u CR_PAT mix format` on the changed Elixir files passed.
- `rtk env -u CR_PAT mix compile --warnings-as-errors` passed.
- `rtk env -u CR_PAT mix credo --strict` on the three changed modules passed.
- `rtk env -u CR_PAT mix test test/cuckoding_web/status_live_test.exs:232 test/cuckoding/board_control_test.exs:1783` passed except two setup failures caused by the sandbox blocking Git hooks; rerun outside the sandbox.
- `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs:597` passed outside the sandbox: 1 test, 0 failures. It reaches Done and shows Open in Finder.
- `rtk git diff --check` passed.
- Authenticated browser observation of the installed app was not repeated; the prior session was unauthorized.

### Paused board blocked planning — 2026-10-02 night

Ask an agent on board `01a0e106-6af2-766a-816e-9521b36053bb` failed because shutdown hibernation left the board paused and startup never reopened admission. The page mapped that failure to a generic agent-settings message, and each attempt left a Ready planning card. Startup now reopens paused-board admission without resuming hibernated runs. A paused board shows Resume board, and planning refuses before creating another card.

- `rtk env -u CR_PAT mix test test/cuckoding/execution/scheduler_test.exs:205 test/cuckoding/execution/scheduler_test.exs:234 test/cuckoding_web/board_live_test.exs:319` passed: 3 tests, 0 failures.
- `rtk env -u CR_PAT mix compile --warnings-as-errors` and `rtk env -u CR_PAT mix credo --strict` on the four changed modules passed.
- `rtk git diff --check` passed.
