# Implementation plan and checklist

**Current implementation audit: 2026-10-24.** The source reset remains historical;
this checklist describes the current local preview. Setup, saved teams, folder
analysis, automatic task cards and the bounded Codex/Cursor Arena loop with task waves
are implemented. Pause/Resume, explicit provider Retry and Skip/Partial are also
implemented. R060d adds safe restart checkpoints and R060e retains expired stage
evidence for verified closure. R012 runs setup/planning in supervised asynchronous
tasks and couples worker/coordinator restarts. R060f commits results before
coordinator notification; R060g reconciles complete retained native integration
receipts to a paused checkpoint without replay. R060m/n add retained writer-
preparation checkpoints; R060o adds capture and mixed capture/preparation
checkpoints with all-member proof and explicit Resume. R060p adds Stop-only
inspection of a provider/capture-or-preparation pair; it never accepts either
interrupted operation. Other interrupted native effects remain open.
R060h fences new battle work on
timing gaps and backward clock changes. R060i adds bounded native idle-system
sleep protection and dated Settings observations. The remaining recovery gates
below still block complete beta acceptance.
R060r permits independent ready work after verified task-local attention and a
clean drain, with unresolved tasks retained and shared failures still closing
the Arena. Schema eighteen protects that new policy from older bundles.
R060j adds bounded automatic provider backoff with SQLite-owned waits and fresh
attempts, inside the existing retry budget; interrupted/native recovery remains open.

| Area | Implemented | Still required |
| --- | --- | --- |
| Agents and Team | Named Codex/Cursor connections, full bounded catalogs, model choices, default/custom planning roles, selected custom read/write stages, scoped team editing/adoption | Claude Code, Hermes and real-provider custom-stage acceptance |
| Arena and tasks | Add folder/default board, versioned column names/ordered custom read/write stages, bounded docs-first analysis, optional saved planning role, automatic cards, prerequisites, citations and saved criteria | Real-account planning/custom-stage acceptance |
| Execution | One Start, two independent task pipelines per wave within two global workers, serialized independent review/correction/integration, task-proposed offline npm/Mix checks, bounded failure feedback and retained local result branch | Dependency/platform verification, real mixed-provider and same-account parallel battle acceptance |
| Controls/recovery | Stop, stage-boundary Pause/Resume, bounded provider Retry and automatic backoff, Skip with deferred dependents and Partial result; settled restart checkpoints, timing fence and bounded idle-sleep assertion | Unfinished native/process/Git reconciliation, sleep accounting and physical sleep tests |
| Experience | Agent wizard/disconnect, Team editor, Arena controls/inspector with public JSON evidence downloads, global workers/progress and paginated global/Arena activity with follow control | Broader parallel activity, responsive/browser acceptance and timed ten-minute setup |
| Release | Local bundle/build/smoke, separate preserved data root; Decimal/Bandit advisories fixed | Signing/notarization, clean-machine install, updates/rollback and full acceptance matrix |

Delivery order: finish uncertain-effect/toolchain recovery (R060), real-provider
parallel and combined-result acceptance (R070), then complete the user-flow/runtime
and release verification gates (R080–R100). The bounded implementation is in place;
unchecked acceptance below remains required.
Task-proposed checks/dependency support and consented live-provider acceptance can progress
alongside recovery. No fixture suite or successful local build substitutes for
those provider/physical/clean-machine gates. Historical slice evidence stays
linked below; completed implementation and remaining acceptance are separate.
R050q lets task analysis propose fixed verification profiles without the optional
Advanced editor. R050r supplies bounded failed-test output to the assigned repair
pipeline under new Start scope. Remaining check work must support dependencies
and verify platform/distribution limits. Local fixture proof does not complete
real-account, recovery or release acceptance.

R015 adds the separately requested public site after R010; see [Site](SITE.md).

Claim exactly one task file when beginning a slice. Use the slice IDs below
for those files and worklogs; do not generate a folder of empty task templates.
Every application slice includes its LiveView surface, durable events, focused
regression checks and documentation update. R080 is cross-screen polish, not the first UI.

## Next delivery order · Simple Arena

The 2026-10-10 simplification takes priority over adding more setup screens.
Normal use is **Add folder → Create tasks → Start**; saved Agents/Team are reused.
The numbered story below is capability coverage, not eight mandatory screens.

- [x] **R002 / R040k — Simple Arena surface:** align docs, add the default board
  atomically with a new Arena, suggest its folder name and open it immediately.
  Keep existing boards and dirty drafts. Move technical setup/additional boards
  to Advanced, make planning prominent and explain unavailable Start inline.
- [x] **R040l — Analyze folder:** bounded host inventory of `docs/` and relevant
  eligible files, versioned finite limits/exclusions, pinned source snapshots,
  clear read/provider-use intent, progress/cancel and useful empty-source guidance.
  No live Arena access for the planning provider and no Git prerequisite.
  Delivered as **Read project folder**, retained source preview and separately
  consented Speculator planning. [Task and evidence](../tasks/R040l-folder-planning.md).
- [x] **R040m — Create cards automatically:** validate and atomically import the
  proposal graph with sources and stable receipts; survive duplicate results and
  restart without duplicates or overwriting user edits. Keep legacy imports readable.
  Delivered for new **Create tasks** requests; no execution grant or schema change.
  [Task and evidence](../tasks/R040m-automatic-task-cards.md).
- [ ] **R020 remaining execution gates:** prove the selected provider's actual
  task grant, tool/output validation, cancellation and two-workspace isolation.
  Catalog/setup acceptance alone does not enable an Implementor.
  R020m adds a repeatable, version-bound two-workspace CLI sandbox diagnostic;
  R020o verifies a synthetic signed-in host-tool read/edit; R050e adds battle
  admission. Real-account multi-task/restart acceptance remains open.
- [x] **R050d — One Start (initial Codex scope):** durable bounded battle authorization and fresh admission
  from the Arena and automatic owned worktree preparation. Existing contextual
  Git/first-commit controls supply a committed source when needed; no mandatory
  preview/spec-acceptance wizard. See [R050e](../tasks/R050e-arena-loop.md).
- [x] **R050e — Work and review loop (initial Codex scope):** Summa Rudis dispatch, Speculator refinement,
  Implementor candidate, independent Secutor verdict, automatic persisted card
  moves and bounded correction through Speculator; reviewed local integration.
- [x] **R050f — Task-owned verification:** generated tasks include expected outcomes
  and verification instructions. New battles need no separate Arena command list;
  independent task/final review remains mandatory. Optional configured commands
  still gate completion; no command execution or pass is inferred from an empty list.
  [Task](../tasks/R050f-task-verification.md) · [evidence](../worklog/2026-10-13-R050f-task-verification.md).
- [x] **R020p — Cursor role execution implementation:** exact selected native model
  variant, restrictive ACP profile and existing host file tools; mixed teams
  without substitution and actionable Start blockers. Fixture tests and native
  metadata preflights pass. [Task](../tasks/R020p-cursor-task-execution.md).
- [ ] **R020p / R090 live acceptance:** consented Cursor read/edit/permission-denial
  sessions and a real mixed-provider battle. Metadata preflights do not prove inference.
- [x] **R060a — Pause/Resume:** finish the bounded current stage, retain its result
  and pause before dispatch; resume a clean durable boundary with the same scope
  and deadline. Stale controls, cleanup uncertainty and interrupted pausing refuse
  continuation. [Task](../tasks/R060a-battle-pause-resume.md).
- [x] **R060b — Provider Retry:** explicit bounded retries for settled transient
  role failures; retain failed edits, fresh writer worktrees, immutable scope and
  all consumed limits. No rejected-review/native-effect replay. [Task](../tasks/R060b-provider-retry.md).
- [x] **R060c — Skip:** confirm a settled task, defer its transitive dependents,
  retain unfinished work and review independent results as Partial. Historical grants,
  uncertain effects and final reviews cannot be skipped. [Task](../tasks/R060c-task-skip.md).
- [x] **R060d — Restart checkpoints:** reopen fully settled running/pausing
  boundaries as Paused with a recorded reason and explicit Resume; retain
  uncertain claims for inspection. [Task](../tasks/R060d-restart-checkpoints.md).
- [x] **R060e — Expired stage evidence:** retain validated late results without
  advancing work; allow confirmed Stop only with all cleanup verified. No Resume,
  Retry, Skip or replay from expired receipts. Packaged smoke and preserved-workspace
  relaunch verified 2026-10-15. [Task](../tasks/R060e-late-stage-receipts.md).
- [x] **R060f — Durable handoff:** workers commit validated setup/battle receipts
  before completion notification. Coordinator crashes retain those facts and
  clean battle checkpoints pause without replay; uncommitted work stays uncertain.
  Invalid/foreign receipts cannot prove cleanup. [Task](../tasks/R060f-durable-worker-handoff.md).
- [x] **R060g — Retained integration:** inspect complete native receipts after
  restart without repeating Git changes; retain Interrupted history and pause
  verified in-budget results for explicit Resume. Missing evidence stays blocked.
  [Task](../tasks/R060g-retained-integration.md).
- [x] **R060h — Timing guard:** independently observe UTC/monotonic gaps, pause
  clean boundaries or cancel/retain active work without advancement; verified
  closure permits Stop. Physical sleep and process/lease reconciliation remain open.
  [Task](../tasks/R060h-timing-gap-fence.md).
- [x] **R060i — Idle-sleep protection:** derive bounded eligibility in Phoenix,
  acquire/renew/release one timed native assertion through the authenticated
  heartbeat and show dated native reports in Settings. No display/lid/forced-sleep
  guarantee or physical recovery claim. [Task](../tasks/R060i-idle-sleep-lease.md).
- [x] **R060j — Automatic provider backoff:** new Starts save 5/20-second waits
  for known settled transient failures, reuse the same two-retry budget and
  revalidate exact bindings/limits before fresh admission. Cancel/Stop/Skip/timing
  fences and restart close the wait; historical Starts remain manual.
  [Task](../tasks/R060j-provider-backoff.md).
- [x] **R070a — Concurrent isolated Arenas:** new Starts permit two supervised
  battle stages globally with one stage per Arena/exact provider connection,
  transactional capacity, fair rotation and independent controls. Historical
  Starts/recovery inspection remain exclusive. Same-board task cloning and
  combined-result review remain open. [Task](../tasks/R070a-arena-workers.md).
- [x] **R080g — Live dashboard/activity:** bounded global worker rows, paginated
  latest Arena progress/attention and direct board navigation; shared scoped
  chronological activity with Older/Newer and Pause/Follow latest. Dirty drafts,
  read position and session boundaries stay intact. [Task](../tasks/R080g-live-arena-dashboard.md).
- [x] **R080a — Direct controls:** confirmed per-agent Disconnect unassigns current
  roles while retaining history; saved roles no longer expire on catalog age alone.
  Create tasks, repository setup and extra boards use dialogs; manual tasks use +
  on Specs/ToDo; team version numbers stay in history. Packaged smoke and preserved
  saved-workspace relaunch verified 2026-10-15. [Task](../tasks/R080a-arena-controls.md).
- [x] **R080b — Disconnect after runtime drift:** when the selected executable
  is unverified, complete exact-connection local deactivation/unassignment with
  an honest Not attempted provider-logout receipt. Preserve native profiles,
  other connections, historical bindings and all busy/battle/form gates.
  [Task](../tasks/R080b-disconnect-runtime-drift.md).
- [x] **R080c — Fast, polished journey (implementation):** saved-state Home, shared five-step
  navigation, directly visible role bindings, contextual board-team dialog and
  compact Start with grouped blockers. Preserve existing setup/authority and
  verify desktop role layout, LiveView behavior and build. Narrow/package browser
  walkthrough and timed ten-minute real-account acceptance stay open.
  [Task](../tasks/R080c-fast-simple-flow.md).
- [ ] **R060 / R070 / R080:** complete recovery, parallel workers, both dashboards
  and timed ten-minute acceptance. Usable Arena UI ships with each earlier slice.

- [x] **R080d — Start binding repair:** preserve submitted agent/model pairs,
  distinguish missing models from missing agents, and route repairs to Team.
  Incomplete drafts warn before Start; scope adoption remains explicit.
  [Task](../tasks/R080d-start-bindings.md).
- [x] **R080e — Disconnect and reset:** recognize verified/historical native
  sign-out correctly, reconnect directly, and provide an explicitly confirmed
  full-workspace reset with a private archive and running-work/path/DB guards.
  [Task](../tasks/R080e-disconnect-reset.md).
- [x] **R080f — Skill-guided flow:** install the requested 25 skills with pinned
  provenance; retain exact board context through Team repairs/Save; confirm team
  adoption with one revision-checked action; suppress equivalent-team noise.
  [Task](../tasks/R080f-guided-flow.md).

[R002 evidence](../tasks/R002-simple-arena-contract.md) records the delivered UI
and automatic-board slice. R040l/m deliver bounded source reading and automatic
card creation. R050e adds the first loop; R070d/e add task waves and assigned
role workers. Next: real-account mixed-task/parallel acceptance, general toolchain checks,
remaining recovery/providers/reviewed task repairs and release gates.

## Sequence and dependencies

`R010 → R020 → R030 → R040 → R050 → R060 → R070 → R080 → R090 → R100`

R010 establishes a safe browser shell; R020 proves one real provider; R050 proves
one autonomous task; R070 adds required parallelism. R090 completes all requested
provider adapters. Earlier demos are milestones, not claims that the requested
product is finished.

| User step | Implementation owners |
| --- | --- |
| 1. Authorize local agents | R020, R090 |
| 2. Fetch/cache models | R020, R090 |
| 3. Roles and Summa Rudis | R030, R050 |
| 4. Arena and Git consent | R040 |
| 5. Tabula and role columns | R040 |
| 6. Tasks from description/files | R040, R050 |
| 7. Autonomous battle/review loop | R050, R060, R070 |
| 8. Both dashboards, logs, parallel clones | R070, R080 |

## R010 — Local application foundation

Depends on R001. Read [architecture](ARCHITECTURE.md), [data](DB.md) and
[security](SECURITY.md).

- [x] Pin a supported Elixir/OTP, Phoenix/LiveView, Ecto/SQLite and Tauri 2
  toolchain; establish the project license/distribution files before shipping.
- [x] Create Phoenix app, SQLite migrations, durable command/event boundary and
  one supervised dispatcher. Preserve older app data in a separate data root.
- [x] Add the minimal Tauri tray: Open Cuckoding, Settings, About, Quit; launch the
  bundled development release and open the loopback LiveView home.
- [x] Implement shell bootstrap, single-use browser handoff, origin/session/CSRF
  protections and owned graceful shutdown.
- [x] Wire RTK/Ponytail defaults and executable discovery; define formatter,
  compiler, ExUnit, Credo, Sobelow and shell quality commands.

Acceptance: launch from the tray, see one browser screen, reject unauthorized/
replayed access, reconnect without data loss, Quit cleans only owned processes.
Run foundation/migration/security/shell checks and record the actual build.

## R012 — OTP execution and LiveView component audit

- [x] Run setup/planning provider I/O in monitored tasks, preserving serialized
  admission and responsive coordinator mailboxes.
- [x] Pair each coordinator/Task.Supervisor under `one_for_all`; interrupt lost
  external claims without replay or assumed native cleanup.
- [x] Keep login progress current-task-bound, transient and redacted from OTP
  error/status reports; retain explicit cancellation/session gates.
- [x] Standardize all four stateful components through the shared LiveComponent
  entry point. Every application screen already uses LiveView; authentication,
  redirects, downloads and native protocol retain their existing boundaries.
- [x] Final quality (322 tests), source/packaged smoke and preserved-workspace
  relaunch. Visual browser recheck unavailable while the Mac was locked.

[Task](../tasks/R012-otp-workers-components.md) ·
[Evidence](../worklog/2026-10-15-R012-otp-workers-components.md).
This refactors execution ownership; product parallelism/full native recovery remain open.

## R011 — Source UI development

- [x] Launch a source server with isolated data and the existing shell/session contract.
- [x] Enable HEEx annotations and standard Phoenix/asset reload in development.
- [x] Explain an already-running source server and retain exclusive data ownership.
- [x] R011d removes the signal/Event shutdown deadlock, fences startup/browser/
  heartbeat work after Stop and verifies real SIGINT/SIGTERM lock/listener release.
  [Task/evidence](../tasks/R011d-launcher-signals.md).
- [x] Remove Tidewave at the user's request; verify absent MCP/toolbar and strict
  application CSP. See [removal evidence](../tasks/R011b-remove-tidewave.md).
- [x] Restore the current packaged app with its saved test workspace after an
  obsolete foundation bundle was opened. Retain separate Agents/Team/Arenas and
  cover these routes in packaged smoke. See [R011c](../tasks/R011c-current-app-launch.md).

The original [R011 installation record](../tasks/R011-tidewave-dev.md) is historical.

## R015 — Satirical Coliseum public site

Depends on R010. User-requested addition; does not block the app's R020 sequence.

- [x] Build native static `site/` with robot gladiators, expressive spectators,
  Roman irony, responsive scroll sections and decorative parallax.
- [x] Preserve no-JavaScript content, keyboard navigation, OS reduced motion and
  a persistent pause control; label concept art and illustrative UI.
- [x] Separate available foundation from planned capabilities and public release.
- [x] Prepare pinned, scoped GitHub Pages workflow; no external publication.
- [x] Verify and integrate into local main; see [task](../tasks/R015-colosseum-site.md) and
  [worklog](../worklog/2026-10-06-R015-colosseum-site.md).

## R016 — Trident identity and Roman revels

- [x] Propagate a trident/code mark across site, app favicon, native and tray icons.
- [x] Add robot leisure and Pan/satyr illustrations, provenance and truthful captions.
- [x] Extend bounded parallax to three scenes with one accessible pause control.
- [x] Verify export, native build/smoke and responsive site behavior; see
  [R016 evidence](../worklog/2026-10-06-R016-trident-revels.md).

## R017 — Cuckoding identity and layered satire

- [x] Use Cuckoding/CC display names and Emperor capitalization; preserve data paths.
- [x] Export the C/furcina tail mark across all brand consumers.
- [x] Compose four scenes from independent backgrounds and character cutouts,
  including scroll-driven weapon crossing and the melancholy human finale.
- [x] Verify responsive, motion and native packaging gates; see
  [R017 evidence](../worklog/2026-10-07-R017-layered-cuckoding.md).

## R018 — Cybernetic Arena visual direction

- [x] Black/electric-green site with original chrome cyborgs and orbital Arena.
- [x] Four layered scenes: sentinel, crossing weapons, Pan/robot dance, melancholy finale.
- [x] Coordinated internal app surfaces, navigation, controls and synchronized green brand assets.
- [x] Truthful shipped/planned copy, prompt provenance, responsive and motion fallbacks.
- Verification and local build evidence: [R018 worklog](../worklog/2026-10-10-R018-neon-arena-design.md).

## R019 — Cinematic Arena scrolling

- [x] Adapt the requested 1367 Studio portrait/camera/editorial pacing with original black/green artwork.
- [x] Add an emissary and orbital-vault plate; preserve layered satire and truthful public claims.
- [x] Bound reversible camera depth; keep pause, reduced motion, native scrolling and no-JS content.
- [x] Verify desktop/narrow rendering and motion checks; record [R019 evidence](../worklog/2026-10-10-R019-cinematic-parallax.md).
- [x] R019a: gothic sci-fi hero/architecture and afterparty costumes; preserve
  independent layers and verify [artwork evidence](../worklog/2026-10-10-R019a-goth-artwork.md).

- [x] R019b: extend gothic harness/collar/cuff fashion to Arena spectators while
  retaining the empty floor and scene layers; see [crowd artwork evidence](../worklog/2026-10-10-R019b-arena-crowd.md).

## R020 — One real agent and durable models

Depends on R010. Start with one of the user's installed supported runtimes
(default implementation order: Codex first); no simulated connection may pass
the real-provider gate.

- [x] R020a: metadata-only discovery, manual Codex executable selection,
  explicitly confirmed version probe, durable readiness and separate authorization
  status. See [task](../tasks/R020-codex-connection.md) and [evidence](../worklog/2026-10-06-R020-codex-connection.md).
- [x] R020b: fixed read-only app-server inspection, stable private profile,
  normalized account observation, bounded model cache with stale retention and
  24-hour freshness, consent/cancellation/reconnect UI. Fresh signed-out Codex
  tested; connected catalog fixtures are not real-account acceptance. See
  [R020b evidence](../worklog/2026-10-07-R020b-codex-connection-inspection.md).
- [x] R020n/o/p extend the pinned Codex/Cursor boundary to structured task turns,
  restricted runtime permissions and host list/read/edit tools. See
  [Codex task routing](../tasks/R020o-task-tool-routing.md) and
  [Cursor execution](../tasks/R020p-cursor-task-execution.md); live gates remain below.
- [x] R020c: app-owned ChatGPT browser login/status/logout, transient protected
  login redirect, cancellation/cleanup, profile serialization and durable
  account/catalog invalidation. Real login start/cancel passed; human-completed
  login remains open. See [R020c evidence](../worklog/2026-10-07-R020c-codex-sign-in.md).
- [x] Fetch/cache full bounded catalogs for connected Codex/Cursor profiles,
  with source/freshness, stale retention and explicit refresh (R020b/f/i/l).
  No invented model IDs, entitlement inference or silent fallback.
- [x] R020d: consented fixed model-access diagnostic, fresh catalog/identity
  binding, restrictive scratch permissions, matching public completion, cancellation
  and no automatic replay. Real unsigned config/thread preflight passed; successful
  responses use protocol fixtures. See [R020d evidence](../worklog/2026-10-07-R020d-model-access-check.md).
- [x] R020e: preserve profile consent through clock/unrelated updates, support
  deliberate unchecking, and reset on submission/setup changes. Reject recovered
  stale forms and expired sessions; verify the rebuilt browser surface. See
  [task](../tasks/R020e-profile-checkboxes.md) and
  [evidence](../worklog/2026-10-08-R020e-profile-checkboxes.md).
- [x] R020f: fetch the full paginated agent model list, retain validated picker
  visibility, and expose additional entries in Agents/Team without inferred access.
  See [task](../tasks/R020f-full-model-catalog.md) and
  [evidence](../worklog/2026-10-08-R020f-full-model-catalog.md).
- [x] R020g: scope connection confirmation resets, hide sign-in while connected,
  and offer an explicit desktop-runtime path choice. Verify the 0.162.0-alpha.2
  account notification and ten-model catalog separately from old 0.146.0.
  See [task](../tasks/R020g-codex-setup-state.md) and
  [evidence](../worklog/2026-10-09-R020g-codex-setup-state.md).
- [x] R020h: four-step Agents wizard, audited saved model selection for new Team
  bindings, optional diagnostics and compatibility with real runtime notices.
  Verified desktop 0.162.0-alpha.17.2 and a real GPT-6.1 Sol browser diagnostic;
  repository execution and broader R020 acceptance remain open.
  See [task](../tasks/R020h-agent-wizard.md) and
  [evidence](../worklog/2026-10-10-R020h-agent-wizard.md).
- [x] R020l: accept Cursor catalogs and saved selections beyond 128 entries while
  retaining bounded complete validation; see [catalog evidence](../worklog/2026-10-10-R020l-cursor-catalog.md).
- [x] R020m: optional Codex isolation diagnostic with fixed commands, two disposable
  workspaces, read-only/writing grants, canaries, timeout/cancellation and audited
  executable-bound receipts. [Task/evidence](../tasks/R020m-codex-isolation.md).
  This proves the tested CLI sandbox behavior, not actual model-tool turns.
- [x] R020n: implement bounded Codex dynamic file-tool transport, exact scoped
  requests, protected paths, compare-before-write and interruption receipts.
  [Task/evidence](../tasks/R020n-task-tools.md). R020o restores task-only Code Mode
  routing; a consented GPT-6.1 Sol synthetic read/edit and normal cleanup passed.
  Broader real-account acceptance remains open; R050e integrates these tools
  into the first sequential Start loop.
- [ ] Prove a read-only turn and a permitted worktree-writing turn in isolated
  workspaces; normalize public activity, outcomes and redacted logs.
- [x] Implement task/process identity, cancellation, clean environments, path
  policy, finite deadlines and fixture conformance (R020n/p, R050e).
- [ ] Complete real-provider read-only/write/denial, interrupted cleanup and
  two-Arena acceptance. R020o's one synthetic read/edit success is partial evidence.

Acceptance: one login supports two Arena-shaped workspaces and different models
across app restart; revoked access and missing models produce actionable errors;
personal profiles are untouched; canaries do not enter artifacts.

## R030 — Saved roles and team

Execution acceptance depends on R020. R030a configuration can ship independently.

- [x] R030a: seed four required responsibilities, edit names/instructions, and
  add/remove custom read-only planning roles with explicit removal confirmation.
- [x] Save unassigned drafts or validated Codex/model bindings; show missing,
  stale, changed or untested models without authorizing work or substitution.
- [x] Persist immutable default-team revisions, idempotent audited saves, stale
  editor rejection and previous-revision inspection in the authenticated UI.
  See [task](../tasks/R030a-saved-team.md) and [evidence](../worklog/2026-10-07-R030a-saved-team.md).
- [x] Inherit teams in new Arenas/Tabulae (R040a/b) and explicitly adopt the saved
  default for existing scopes (R030b), preserving historical snapshots. See
  [task](../tasks/R030b-scoped-team-adoption.md) and
  [evidence](../worklog/2026-10-07-R030b-scoped-team-adoption.md).
- [x] R030c edit role overrides per Arena/Tabula through the shared Team editor,
  with immutable scope-bound saves and independent defaults. Preserve active
  planning, model, removal, session and form gates; navigation never adopts.
  [Task/evidence](../tasks/R030c-scoped-team-editor.md).
- [x] R030d keep custom planning-only roles available without blocking Start;
  bind only the four existing execution responsibilities and disclose extras in
  Inspect. No custom execution stage is implied. [Task](../tasks/R030d-planning-role-start.md).
- [x] R070e optional exact second bindings per required role in Team; immutable
  scoped/default saves, explicit adoption, catalog/Disconnect gates and frozen
  Start allocation. Separate sessions/worktrees; one exact connection still
  serializes turns. [Task](../tasks/R070e-assigned-workers.md).
- [ ] Prove real-account independent sessions, including a shared provider account,
  without inferring permission from role text or cloning authorization.

Acceptance: save the team once, reuse it without per-task assignment, change a
future default without changing an existing snapshot, and reject permission
expansion from role text.

## R040 — Arena, Tabula and planning

Depends on R030.

- [x] R040a: register canonical local folders using a native chooser, explicit
  confirmation and frozen default-team revision. Accept empty/document/Git-entry
  folders without content reads or writes; reject duplicates/replaced identities.
  See [task](../tasks/R040a-arena-registration.md) and [evidence](../worklog/2026-10-07-R040a-arena-registration.md).
- [x] R040c: inspect missing/unborn/committed standalone Git repositories and
  confirm init separately; preserve existing files and refuse external metadata.
  See [task](../tasks/R040c-arena-git-setup.md) and [evidence](../worklog/2026-10-07-R040c-arena-git-setup.md).
- [x] R040d: preview/authorize bounded initial-commit file selection separately;
  preserve working files and revalidate the exact candidate, branch and absent
  index/refs. Retain partial effects without replay. See
  [task](../tasks/R040d-initial-commit.md) and [evidence](../worklog/2026-10-07-R040d-initial-commit.md).
- [x] R040b: create multiple Tabulae per Arena with Specs, ToDo, In Process,
  Review, Completed and inherited stage roles. Draft/edit tasks with immutable
  history and accessible Specs/ToDo movement; delivery stages remain locked.
  See [task](../tasks/R040b-tabula-drafts.md) and [evidence](../worklog/2026-10-07-R040b-tabula-drafts.md).
- [x] R040e: use the frozen Speculator with a typed brief and explicit usage
  consent; validate/store up to six public proposals and import each into Specs
  once with provenance. No project reads/tools or battle authority. See
  [task](../tasks/R040e-brief-planning.md) and [evidence](../worklog/2026-10-07-R040e-brief-planning.md).
- [x] R040f: preview up to four selected text documents, persist exact snapshots,
  then freeze them in separately consented planning. Reuse no-tools permissions
  and source-command provenance; no directory crawl or delivery work. See
  [task](../tasks/R040f-document-planning.md) and
  [evidence](../worklog/2026-10-07-R040f-document-planning.md).
- [x] Add/rename/reorder bounded custom columns and assign roles through versioned
  definitions (R040o/R050g/R050h). Core order stays fixed; mandatory independent
  Secutor review follows all custom writing stages.
- [x] R040o establishes the immutable per-board workflow ledger and Advanced
  column-name editor, with exact scope/revision/session gates and frozen Start
  definitions. Existing rows remain revision zero. This completes renaming only;
  R050g/R050h add ordered custom stages and explicit grants below.
  [Task/evidence](../tasks/R040o-workflow-revisions.md).
- [x] Create/edit manual drafts and assigned-Speculator tasks from briefs, selected
  files or bounded folder snapshots. Retain criteria, source citations, prerequisites,
  accepted-spec artifacts and edited cards (R040b/e/f/h/i/l/m).
- [x] R040n optional saved planning-role selection in Create tasks, with exact
  board-team/role/agent/model/source consent and legacy Speculator compatibility.
  Battle-time preparation keeps its existing frozen binding; no custom execution
  stage is implied. [Task/evidence](../tasks/R040n-planning-role.md).
- [x] R020r initial task generation through the exact assigned Cursor connection,
  isolated no-tools ACP, validated v3 snapshots/graph and automatic cards. Keep
  real-account acceptance open. [Task/evidence](../tasks/R020r-cursor-planning.md).
- [x] R040g: select bounded same-board task prerequisites, reject cycles against
  the latest graph and retain dependency revisions without launching work. See
  [task](../tasks/R040g-task-prerequisites.md) and
  [evidence](../worklog/2026-10-07-R040g-task-prerequisites.md).
- [x] R040h: validate prerequisite-first proposal graphs and selected-snapshot
  citations; resolve imported prerequisites and preserve original source linkage.
  See [task](../tasks/R040h-proposal-links.md) and
  [evidence](../worklog/2026-10-07-R040h-proposal-links.md). Citation meaning and
  accepted-spec validation remain separate from reference validation.
- [x] Persist explicit check declarations separately from proposals (R040j);
  R050e freezes them under the bounded native single-process grant.
- [ ] Complete subprocess/toolchain verification, project dependency provisioning
  and platform acceptance. R050q adds task-proposed fixed offline npm/Mix scopes;
  generated task text must not grant execution permission.
  R060o investigation confirmed the installed Apple SDK marks NOTE_TRACK child
  tracking unsupported; removing RLIMIT_NPROC would not establish ownership of
  escaped sessions. A verified containment/cleanup design remains required.
  R050i's disposable Darwin probe also observed child session/group escape under
  deny-default Seatbelt with fork enabled. Group cleanup alone is insufficient;
  retain the historical system grant's no-fork limit; guest checks use a separate
  VM lifetime boundary and frozen policy.
  [Investigation](../tasks/R050i-toolchain-containment.md).
- [x] R050j prototype a bounded isolated guest with pinned official inputs and
  no network/host shares. Actual native Stopped observations pass for input,
  controller EOF, deadline and paused VM; abrupt owner loss remains unverified.
  Keep shipping grants unchanged. [Task/evidence](../tasks/R050j-guest-lifetime-prototype.md).
  Production implementation still needs protected transport/owner-loss closure,
  private candidate/image transport, frozen grants/receipts/OTP integration and
  packaging/licensing/acceptance. R050l supplies separate actual-toolchain probe
  evidence below.
- [x] R050k verify non-root/no-new-privileges workers, nondelegated kernel
  PID/memory/CPU budgets, session containment and a separately protected guest
  watchdog under fixed adverse workloads. Client EOF with a live keeper reaches
  native guest shutdown; abrupt keeper death remains unverified. The root-worker
  mutation refuses. No shipping grant changes.
  [Task/evidence](../tasks/R050k-protected-guest-watchdog.md).
- [x] R050l verify actual offline npm/Mix pass/fail checks against synthetic Git
  candidates in the protected guest. Bind exact scope and output to privileged
  control plus native shutdown; refuse worker forgery, changed source and oversized
  output. Cancellation carries no invented exit; keeper loss remains unverified.
  Production grants remain unchanged. [Task/evidence](../tasks/R050l-offline-toolchain-checks.md).
- [x] R050m production candidate-input transport: fixed native prepare/verify,
  immutable blobs, descriptor-pinned private newc/manifest/intent/receipt, exact
  scope/hashes/counts and read-only recomputation. Keep execution grants unchanged.
  [Task/evidence](../tasks/R050m-candidate-check-input.md).
- [x] R050n fixed production image installation and protected guest runtime:
  pinned upstream inputs, exclusive private receipts, read-only image verification,
  bounded unprivileged npm/Mix and separate typed control/output. Actual synthetic
  candidate checks use the production image; Start grants remain unchanged.
  [Task/evidence](../tasks/R050n-frozen-check-image.md).
- [x] R050o production native VM keeper: exact image/candidate/check scope,
  dedicated entitlement, bounded private output, original deadline, EOF cancellation,
  SDK Stopped plus helper-group closure and retained exact receipt. VM-only closure
  after wrapper loss remains insufficient for overall cleanup/recovery.
  [Task/evidence](../tasks/R050o-native-check-keeper.md).
- [x] R050p integrate already-declared offline npm/Mix checks into supervised OTP
  execution and a frozen Start grant. Existing admission owns first-use image
  installation/reuse; one Start, exact original check receipts and independent
  review, no extra setup action. Preserve old grants and unknown-cleanup capacity.
  Seven actual VM checks complete two dependent tasks with a forced review return;
  providers are synthetic. Image reuse/Pause/Stop and old-bundle refusal pass.
  [Task/evidence](../tasks/R050p-arena-guest-checks.md).
- [x] R050q task-owned fixed npm/Mix profiles without routine Advanced setup,
  immutable v4 proposals/task revisions, per-task/integrated/final retained scope,
  guarded task dialog and forward-only schema twenty. Start grants the exact
  bounded guest scope; historical contracts and configured requirements remain.
  Six real VM checks finish generated dependent tasks with failed-test correction,
  final review, image reuse/Pause/Stop and a schema19-to20 bundle fence; providers
  are synthetic. [Task/evidence](../tasks/R050q-task-checks.md).
- [x] R050r bounded failure output for the assigned repair pipeline, with opt-in
  native projection after verified closure, immutable attempt/candidate binding,
  unchanged prompt/runtime bounds and metadata-only public history/downloads.
  Six actual VM checks verify failed-test delivery, repair, clearing old feedback,
  final review, image reuse/Pause/Stop and the schema20-to21 old-bundle fence;
  providers remain synthetic.
  [Task/evidence](../tasks/R050r-check-feedback.md).
- [x] R060t native read-only inspection of complete retained guest-check proof.
  Exact original bindings, frozen image/candidate/output and both closure records;
  no VM/command launch, artifact replay or workflow authority.
  Six actual guest receipts pass repeated exact reads; foreign/partial proof
  refuses with original artifacts intact. OTP recovery remains the next item.
  [Task/evidence](../tasks/R060t-retained-guest-check.md).
- [ ] Wire complete retained-check inspection into the supervised OTP recovery
  queue. Preserve Interrupted attempts and dated observations, require every
  original ordered check and pause for explicit Resume under original budgets.
  Missing/partial/expired/fenced proof must never accept work or rerun tests.
- [ ] Provision project dependencies and verify
  platform/distribution/licensing. Hard VM-owner loss requires recovery evidence;
  synthetic checks never establish real-provider or release acceptance.

- [x] R040j: explicit check preview/consent, immutable Arena revisions, idempotent
  audited saves, stale/recovered editor refusal and no implied execution authority.
  See [task](../tasks/R040j-project-checks.md) and
  [evidence](../worklog/2026-10-08-R040j-project-checks.md).
- [x] R040i: preview/accept exact saved intent as private Markdown, bind task and
  prerequisite revisions, verify hashes and preserve historical artifacts after edits.
  Acceptance/ToDo/history/events commit together; uncertain writes never replay.
  See [task](../tasks/R040i-accepted-specifications.md) and
  [evidence](../worklog/2026-10-07-R040i-accepted-specifications.md).

Acceptance: add an empty folder and one with docs; get a default board immediately.
Create tasks analyzes eligible sources and persists usable cards/citations without
manual paths or per-card imports. Reanalysis preserves edits. Declining Git setup
leaves planning usable and files unchanged; custom columns cannot bypass review.

## R050 — First autonomous battle

Depends on R040. This is the first end-to-end product milestone.

- [x] R050a: show the assigned team, saved tasks/prerequisites, current verified
  Markdown, declared checks and latest Git observation in a read-only preparation
  preview. Mark stale evidence and link to settings; no execution authority.
  See [task](../tasks/R050a-battle-preview.md) and
  [evidence](../worklog/2026-10-08-R050a-battle-preview.md).
- [x] R050b: prepare a bounded detached locked worktree from a fresh consented HEAD,
  keep original files/index intact, retain private ownership and durable receipts,
  and reject stale/cancelled/expired success without replay. No execution authority.
  See [task](../tasks/R050b-owned-worktree.md) and
  [evidence](../worklog/2026-10-08-R050b-owned-worktree.md).
- [x] R050c: inspect completed worktrees against retained ownership/registration,
  index and raw tracked bytes; preserve files and reject unsafe/foreign/late results.
  Dated observations never grant execution. See [task](../tasks/R050c-worktree-inspection.md)
  and [evidence](../worklog/2026-10-08-R050c-worktree-inspection.md).
- [x] R050d1: retain exact task candidates through closed host Git operations,
  verify raw bytes and preserve original checkouts/indexes/branches. No Start
  authority or independent verdict is implied. See [task/evidence](../tasks/R050d1-task-candidates.md).
- [x] Implement one Start authorization for goal/spec, task membership,
  team, model, policy, base revision, check commands and cumulative limits.
- [x] Give Summa Rudis a closed decision contract; host-validate/persist decisions
  and route every launch through common admission.
- [x] Run Speculator → Implementor → Secutor with explicit spec/candidate/evidence
  handoff; return all review comments to Speculator before another implementation.
- [x] Execute confirmed bounded custom stages in order with their explicit read/write
  grants (R050g/R050h); real-provider acceptance remains a separate open gate.
- [x] R050g executes up to four explicitly selected custom read roles between
  Speculator and Implementor, with immutable order/bindings, existing read tools,
  finite budgets/capacity, automatic card movement and mandatory Secutor review.
  Advanced supports Add/Up/Down/Remove; unused roles stay planning-only. R050h
  extends this historical read-only contract below.
  [Task/evidence](../tasks/R050g-read-role-stages.md).
- [x] R050h adds explicit custom writers and read stages before/after Implementor.
  Version-four workflows freeze grants/order; every writer captures cumulative
  immutable edit evidence and subsequent stages verify the retained checkpoint.
  Retry starts fresh preparation/Speculator; independent review still gates final
  integration. No new provider/native tools or per-task setup. The seventeenth migration indexes writer evidence and prevents old bundles from misinterpreting the policy; back up first.
  [Task/evidence](../tasks/R050h-custom-writers.md). Real-account acceptance remains open.
- [x] Retain independent Secutor sessions; bind passes to exact criteria, Git
  heads and host-check receipts. Summa Rudis cannot override rejection.
- [x] Integrate locally into a battle branch, run final checks and final Secutor
  assessment, then show a complete result with branch/spec/review/log links.
- [ ] Permit reviewed in-scope repairs/splits while preserving original criteria,
  task lineage, lifetime counters and authorization.

R050e code/fixture scope: Codex default stages, 20 tasks, three review returns,
200 turns, two-hour wall limit; no ordinary per-task prompts. Historical host checks use
`codex-check-single-process-v1`: native system commands, no spawned toolchain
processes. A failed final review requires attention. Source checkout stays intact;
Start never pushes or merges into the user branch. Stop and fail-closed restart
are implemented. R060a adds Pause/Resume at completed stage boundaries;
R060b adds bounded provider Retry; R060c adds confirmed Skip with deferred dependents
and reviewed partial results. Full reconciliation remains R060.

Real-account acceptance remains open: one Start completes a two-task dependency chain with a forced review
return and no ordinary human prompts. A forged/stale completion cannot advance
state. New unrelated tasks remain outside the running battle. No remote Git
operation or user-checkout merge occurs.

## R060 — Controls and durable recovery

Depends on R050.

- [x] R060a Pause/Resume at completed stage boundaries; R050e Stop with cleanup.
  Keep durable intent, pending states, unchanged limits and retained artifacts.
- [x] R060b explicit provider Retry with settled cleanup and frozen lifetime limits.
- [x] R060c Skip at settled task boundaries, deferred dependents and partial results.
- [x] R060d settled restart checkpoints with explicit Resume and unchanged budgets.
- [x] R060e late receipt retention and verified Stop, without accepting expired work.
- [x] R060f worker-side settlement before notification; preserve committed results
  across coordinator crashes without replay or trusting malformed cleanup flags.
- [x] R060g inspect complete retained integration receipts after restart, preserve
  interrupted attempts and pause verified in-budget results for explicit Resume.
  Missing receipts and other native/provider stages remain needs-attention.
  [Task and evidence](../tasks/R060g-retained-integration.md).
- [x] R060k explicit bounded native group closure and fail-closed receipt
  normalization; retain uncertain effects/session stores without success or
  cancellation promotion. [Task/evidence](../tasks/R060k-provider-cleanup.md).
- [x] R060l retain exact public provider closure before reply; supervised restart
  inspection can enable confirmed Stop and connection release without accepting
  or replaying the interrupted work. Missing receipts/hard-kill remain open.
  [Task/evidence](../tasks/R060l-retained-provider-closure.md).
- [x] R060m inspect complete retained writer preparations through the exclusive
  supervised recovery path. Keep Interrupted history and dated observations;
  pause verified in-budget checkpoints for explicit Resume. Missing/foreign/
  partial evidence, preexisting Stop/timing fences and multiple unfinished native
  stages remain blocked. [Task/evidence](../tasks/R060m-retained-preparation.md).
- [x] R060n queue two exact retained preparations under a new Start policy, read
  exclusively and checkpoint both tasks atomically only after both proofs pass
  within all original limits. Partial/failed/mixed/fenced waves never advance.
  Older snapshots retain single-claim limits. [Task/evidence](../tasks/R060n-wave-preparation.md).
- [x] R060o reads complete retained capture evidence for one/two captures or a mixed
  capture/preparation pair. Exclusive supervised reads retain immutable history,
  commit every next stage together and pause for explicit Resume. Missing proof
  never replays capture; expired/fenced reads permit verified Stop only.
  [Task/evidence](../tasks/R060o-candidate-recovery.md).
- [x] R060p reads retained closure for one interrupted provider plus a native
  capture/preparation. Queue provider first and then native in exclusive workers;
  preserve every Interrupted claim and task/head/budget/deadline. Only all-claim
  verified closure permits Stop; no Resume/Retry/Skip or work acceptance.
  [Task/evidence](../tasks/R060p-mixed-closure.md).
- [ ] Broader interrupted-work recovery with verified process cleanup.
- [x] R060s inspect one exact complete retained combined candidate under a new
  Start policy, without recombination or missing-proof reconstruction. Reuse the
  exclusive supervised queue; pause for explicit Resume and fresh checks/review.
  Fix the actual host/native preparation mismatch; packaged CLI proof preserves
  edits/index/receipts and refuses missing proof/replay. Historical/mixed scopes
  and original bounds stay unchanged. Broader recovery
  remains open. [Task/evidence](../tasks/R060s-combination-recovery.md).
- [x] R060h timing-gap admission/settlement fence with independent supervised
  clock observation, clean Pause and rejected active receipts; no claim of sleep.
- [x] R060i fixed native idle-system sleep lease during eligible work, bounded
  renewal/release, nonfatal failure and dated authenticated observations.
- [x] R060j bounded automatic backoff for known settled provider failures,
  separate retry/review counters and unchanged deadlines; no repeated sign-in
  requests per task. Historical Starts retain explicit Retry.
- [ ] Broader provider-specific rate-limit classification and recovery acceptance.
- [x] R060q classifies scoped typed Codex overload/usage/auth/HTTP-429 failures,
  preserves bounded internal retry notifications and retained effects, and adds
  v2 overload backoff within existing lifetime limits. Ambiguous 429 stays manual;
  quota does not retry. v1 behavior remains readable. Cursor/real-provider rate
  acceptance is still required. [Task/evidence](../tasks/R060q-provider-failures.md).
- [ ] Reconcile DB/process/transport/worktree/Git/port ownership before startup
  admission; never blindly replay uncertain work.
- [ ] Reconcile actual sleep/wake and resource leases, preserve active/wall
  accounting, and verify the idle-sleep assertion during physical sleep drills.
- [x] R060r classifies verified task blockers/exhausted task review separately from
  shared/uncertain failures. Drain current stages, continue ready independent work
  with exact evidence/bindings/limits, retain unresolved tasks/dependents and show
  compact task/Arena attention. Pause/restart still require explicit Resume and
  final completion waits for decisions. Real-provider acceptance remains open.
  [Task/evidence](../tasks/R060r-task-local-blockers.md).
- [ ] Preserve input/focus and reconnect both UI and workers safely.

Acceptance: crash before/after launch and integration, lost transport, rate-limit
wait, revoked auth, PID reuse and budget exhaustion produce correct durable
states without duplicate execution. Pass simulated and physical sleep/wake tests
separately. Stop preserves changes and cannot kill an unrelated provider app.

## R070 — Parallel workers and safe combined results

Depends on R060. Required for the requested release, not a deferred enhancement.

- [x] R070a cross-Arena foundation: two supervised battle workers, transactional
  global/Arena/exact-connection caps, fair dispatch, retained uncertain ownership
  and isolated Stop/Pause/crash handling. Prior-schema upgrade/backup covered.
  This does not complete the task-level acceptance below.
- [x] R070b native prerequisite: combine compatible bounded captured paths on the
  exact reviewed head, retain immutable artifacts/ref, prepare a fresh review
  checkout and verify serialized integration/recovery. Conflicts refuse safely.
  No Start policy or same-board lane is enabled. [Task](../tasks/R070b-combined-candidate.md).
- [x] R070c shares the existing attempt-bound receipt validator across settlement,
  controls and recovery before adding lane state; no policy/data changes.
  [Task](../tasks/R070c-stage-receipts.md).

- [x] R070d bounded task waves: independent ready pipelines, per-task claims,
  exact-connection/global caps, serialized combined review/integration, bounded
  conflict repair, multi-worker controls and individually scoped closure reads.
  [Task](../tasks/R070d-parallel-waves.md). Native/fixture proof is separate from
  real-provider acceptance; shared role connections still serialize their turns.
- [x] R070e explicitly assigned paired role workers using separate named
  connections/sessions/worktrees, with stable allocation and no login clone or
  busy-binding fallback. [Task](../tasks/R070e-assigned-workers.md).
- [ ] Prove these pairs with real providers and independent same-account sessions.
- [ ] Atomically claim tasks, capacity and ports; enforce global/Arena/Tabula/
  provider caps, fairness and one active battle per Arena.
- [x] Dispatch independent task pipelines concurrently in bounded waves; wait for integrated prerequisites. Real-provider acceptance remains below.
- [x] Serialize integration; if the battle head changed, validate/test/review the
  combined candidate and compare-and-swap the head.
- [x] Route compatible-combination conflicts to bounded spec/implementation repair; retain every branch
  and failed integration candidate.
- [ ] Recover uncertain Git effects and expired claims without duplicate work;
  reserve scheduling opportunity for coordinator/review to avoid starvation.

Acceptance: run two independent tasks concurrently, a third dependent task after
both, a deliberate overlap/conflict, two Arenas and a crash during integration.
No lost code, duplicate claims, stale review acceptance or premature Completed.

## R080 — Tabula Gladiatorum and ten-minute experience

Depends on R070 for final acceptance. R040k and each execution slice deliver their
usable Arena surface first; basic flow simplification must not wait for R080.

- [x] R080g/R080i global dashboard: Arena summaries, public setup/planning/battle
  work, progress and attention from retained SQLite state. Bounded saved records
  are observations, not proof of native session liveness; real acceptance stays open.
- [x] R080i Arena dashboard: selected Tabula, saved team/progress and exact-board
  worker details using the same durable projections inside Board activity.
  [Task/evidence](../tasks/R080i-board-activity.md).
- [x] R080h task inspector: frozen spec, public review comments, exact bindings,
  candidate/edit/tool/check receipts and 20-attempt cursor pages across retained
  executions, inside the existing task dialog. No new execution authority.
  [Task and evidence](../tasks/R080h-task-evidence.md).
- [x] R080j authenticated public evidence JSON downloads from the task inspector:
  exact execution/scoped cursor, 20-attempt pages, dated frozen/public fields and
  2 MiB limit; no arbitrary file/log access or workflow effects.
  [Task and evidence](../tasks/R080j-evidence-download.md).
- [x] R080g scrollable/paginated normalized event activity globally/per Arena,
  with explicit follow control. Raw provider output/thoughts never enter this feed.
- [x] R080k verifies eight setup-to-Start pages at 320/768/1024/1440 CSS pixels,
  keyboard access to the last custom column and twelve native dialog states.
  Custom columns stay in one row; task editing opens after server selection and
  preserves dirty text. [Task/evidence](../tasks/R080k-responsive-flow.md).
  Human timing, screen-reader/zoom and real-provider acceptance remain open.
- [ ] Safe opening/export of any additional retained log artifacts where supported; full
  parallel-worker and end-to-end dashboard acceptance.
- [ ] Apply the one/two-region modern TUI visual contract, mouse/keyboard
  alternatives, non-color status, responsive layout and reduced motion.
- [ ] Remove duplicate start paths and per-task setup; keep provider internals in
  inspect views and preserve user text/focus across updates.
- [ ] Time an unfamiliar user's first launch through ready-to-start; fix any
  repeated assignments, missing defaults or unexplained states.

Acceptance: user identifies who does what globally and per Arena, opens old/new
log chunks, pauses/retries by keyboard and completes the setup target. Record
rendered desktop/narrow screenshots and observed timing with prerequisites.

## R090 — Complete requested runtime coverage

Depends on R080 for final user-flow acceptance; reuse R020's adapter boundary.

- [x] R020s verifies the installed Codex `0.163.0-alpha.11.2` alongside the old
  execution cohort with fresh-profile non-inference setup/policy/thread and OS
  canaries. Disable new action/daemon defaults and bind isolation receipt versions
  exactly; do not infer real-account execution acceptance from these checks.
  [Task/evidence](../tasks/R020s-codex-compatibility.md).

- [ ] Claude Code: verify current official interface/license, safe authorization,
  model discovery/defaults, grant mapping, streaming, cancellation and recovery.
  Authentication selected: subscription sign-in after Anthropic approval. Approval
  is unconfirmed; keep login/execution unavailable. [Decision](../tasks/R090a-claude-auth-decision.md).
- [ ] Cursor: complete real-account conformance, history cleanup and project-config
  isolation acceptance; setup/catalog and R020p role execution are implemented.
- [ ] Hermes: verify the intended official distribution/interface, license and
  all the same capabilities; record unsupported functions explicitly.
- [ ] Re-run Codex acceptance on the pinned shipping version.
- [ ] Exercise a mixed-runtime team and parallel same-account sessions.
- [ ] Degrade gracefully when one runtime is missing, disconnected or unsupported.

Acceptance: each advertised runtime passes shared conformance and real-provider
two-Arena/login/restart/review/cancellation tests. A capability gap stays an open
item and is reported to the user; it is not silently counted as provider support.

## R100 — Package and prove the story

Depends on every previous slice.

- [x] R100a local preview verification: seal and strictly verify the complete
  ad-hoc bundle, reject modified resources, smoke the authenticated dashboard
  and setup routes, and upgrade an integrity-checked retained-data copy from
  eleven to fourteen migrations without changing saved records. This is not
  notarization, a clean-machine test or real-provider acceptance.
  [Task and evidence](../tasks/R100a-local-beta-verification.md).
- [x] R100b identifies local packages with a shared compiled native/BEAM manifest,
  source/input digest and private immutable artifact receipt. Mixed/missing
  identities refuse before data/dispatch; Settings distinguishes packaged and
  source UI. [Task/evidence](../tasks/R100b-build-identity.md). This is not signed,
  reproducible, clean-machine or real-provider release acceptance.
- [ ] Reproducible signed/notarized Apple Silicon application with bundled release
  and verified helper provenance; no developer toolchain needed by the user.
- [x] R100c verified database-only copy before existing-schema migrations, private
  immutable receipt and dated Settings metadata. Fresh/current startup remains
  fast and failed copies refuse migration. Full restore/import/update and physical
  power-loss acceptance stay separate. [Task/evidence](../tasks/R100c-upgrade-backups.md).
- [x] R100d repeatable sealed-app interrupted-combination checkpoint proof, using
  fresh synthetic workspaces with actual native Git and normal startup/OTP recovery.
  Preserve history/budgets/source and refuse missing proof/replay; verify bounded
  input/EOF/timeout lifecycle cleanup. Real-account and complete recovery gates
  remain separate. [Task/evidence](../tasks/R100d-packaged-recovery-proof.md).
- [ ] Clean-machine install/launch/quit and login persistence; document provider
  prerequisites separately.
- [ ] Prior-data backup/import or safe explicit separate-data behavior; verify
  recovery and prevent accidental old-database overwrite.
- [ ] Signed update, migration and rollback/recovery path that preserves evidence;
  no update while owned mutations are uncertain.
- [ ] Run the complete [acceptance matrix](TESTING.md): ten-minute setup, file
  planning, custom role/column, review loop, parallel conflict, both dashboards,
  logs, provider interruption, restart, sleep and final local result.
- [ ] Record source revision, build identity, actual launched artifact, provider
  versions, commands/results and remaining limitations. Recreate release CI
  only when the invoked scripts exist and have passed.
- [ ] Publish user-facing claims only from this evidence, with separate human
  approval for external release.

Definition of done: all eight story steps work in the packaged app, required
checks pass, no required criteria remain unresolved, and no old test count or
mock provider is used as current release evidence.

## Deferred work

No plugin marketplace, vector/indexing server, autonomous knowledge pipeline,
remote/container workers, automatic push/PR/merge or
analytics suite in these slices. Add only for a concrete later user need.
Use `rtk rg`, existing project skills and scoped Markdown files now.

## R020i · Multiple named agents

- [x] Named Codex/Cursor roster, per-connection wizard/profile/catalog/selection.
- [x] Mixed per-role bindings, scoped model pickers and exact Codex planning routing.
- [x] Cursor fixed setup conformance; no inferred execution support.
- [x] Prior-schema preservation, quality/build/native checks and browser roster check.
  Full interactive wizard QA was interrupted by active browser use; LiveView regressions pass.
- [x] Docs and local main integration; no publication.

See [task](../tasks/R020i-multiple-agents.md) and
[worklog](../worklog/2026-10-10-R020i-multiple-agents.md).

R020l subsequently verified the real signed-in Cursor catalog. Cursor inference
and full mixed-runtime/restart/parallel acceptance remain in R090; fixture Grok
entries alone do not establish model availability.

## R020j · Navigation routes

- [x] Agents `/agents`, wizard `/agents/:id`, Settings `/settings`; sidebar and tray aligned.
- [x] Legacy redirects and canonical shell handoffs preserve session/origin protection.
- [x] Regression checks, packaged build/smoke, running artifact and local main integration.

See [task](../tasks/R020j-navigation-routes.md) and
[worklog](../worklog/2026-10-10-R020j-navigation-routes.md).

## R020k — Explicit connection wizard Next

- [x] Always show step-2 Next with Back and clear unavailable-state guidance.
- [x] Connected Codex/Cursor users can inspect/retry stale catalogs on step 3.
- [x] Preserve pending/version/account gates, fresh-catalog saves and model choices.
- Evidence: [R020k worklog](../worklog/2026-10-10-R020k-wizard-next.md).

## R020q — Fast agent connection

- [x] Editable provider-name defaults, metadata-discovered Cursor executable and
  source launcher discovery hint; no copied profiles or expanded runtime grant.
- [x] Signed-in-only Refresh and one-click pending-tab handoff through the existing
  exact-command/session-protected redirect, with an in-place manual fallback.
- [x] Focused LiveView/hook checks, a synthetic browser popup check, quality/build/
  smoke and preserved-workspace relaunch. Live-provider authorization acceptance
  remains separate. [Task](../tasks/R020q-agent-connect.md).

## R101 — Dependency security maintenance

- [x] Upgrade Decimal beyond CVE-2026-97853 affected versions; retain compatible
  Ecto/SQLite constraints and verify quality/production compilation.
  [Evidence](../worklog/2026-10-13-R101-decimal-security.md).

- [x] R102 Bandit 1.13.1 / Thousand Island 1.6.0: fix current authority/deadline
  advisories, check Hex metadata before application tasks and retain real-loopback
  authority/origin/Phoenix parser-error regressions. No HTTP/2 attack-drill claim.
  [Evidence](../worklog/2026-10-21-R102-bandit-security.md).
- [x] R103 updates only Tokio 1.53.2 → 1.53.3 for the
  [AsyncFd advisory](https://rustsec.org/advisories/RUSTSEC-2026-0386.html), with
  locked native checks and rebuilt sealed lifecycle/recovery verification.
  [Evidence](../worklog/2026-10-24-R103-native-tokio.md).
- [ ] Review the seven remaining transitive native warnings before release:
  five unmaintained `unic-*` crates remain in the Apple Silicon normal/build
  graph through urlpattern/Tauri. `proc-macro-error` maintenance and `glib`
  unsoundness warnings are absent from that target graph but remain in the
  cross-platform lockfile. Do not infer zero risk or suppressions from an
  exit-zero audit; replacement/upgrade or explicit release disposition is open.
