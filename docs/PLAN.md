# Implementation plan and checklist

**Rebuild baseline: 2026-10-06. R010 foundation is verified for local main.**
R001 and R010 establish the documentation contract and local application shell.
See [R010 evidence](../worklog/2026-10-06-R010-local-foundation.md).
Agent authorization, models and orchestration remain R020–R100.
R020a–d complete version readiness, private-profile inspection, validated model
caching, managed sign-in/out and the fixed model-check controls. Real-account/model/execution acceptance
is still open. R030a delivers independently testable saved-team configuration;
R040a adds Arena registration and frozen team inheritance; R040b adds default
Tabulae and manual draft tasks; R040c adds explicit Git inspection and confirmed
initialization. R040d adds explicit file previews and consented initial commits.
R040e adds consented Speculator proposals from typed briefs and individual imports
into Specs. R040f adds explicit selected-document previews and consented snapshot
inputs. R040g adds revisioned, acyclic manual task prerequisites; R040h adds
Speculator prerequisite proposals and per-task snapshot references. R040i adds
explicit accepted Markdown specifications. R040j adds confirmed Arena check declarations.
Dependency scheduling, check execution and execution grants remain open.
R030b lets existing Arenas/Tabulae explicitly adopt a newer saved default team
without rewriting earlier requests or drafts. Per-scope role editing remains open.
Historical source/tests/builds do not satisfy these gates.

R015 adds the separately requested public site after R010; see [Site](SITE.md).

Claim exactly one task file when beginning a slice. Use the slice IDs below
for those files and worklogs; do not generate a folder of empty task templates.
Every application slice includes its LiveView surface, durable events, focused
regression checks and documentation update. R080 is cross-screen polish, not the first UI.

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
- [ ] Extend the implemented adapter version boundary to the owned structured
  runtime transport, permissions and operations below.
- [x] R020c: app-owned ChatGPT browser login/status/logout, transient protected
  login redirect, cancellation/cleanup, profile serialization and durable
  account/catalog invalidation. Real login start/cancel passed; human-completed
  login remains open. See [R020c evidence](../worklog/2026-10-07-R020c-codex-sign-in.md).
- [ ] Fetch models after login; cache bounded IDs/options/source/freshness in
  SQLite, with stale catalog, manual refresh and validated fallback behavior.
- [x] R020d: consented fixed model-access diagnostic, fresh catalog/identity
  binding, restrictive scratch permissions, matching public completion, cancellation
  and no automatic replay. Real unsigned config/thread preflight passed; successful
  responses use protocol fixtures. See [R020d evidence](../worklog/2026-10-07-R020d-model-access-check.md).
- [ ] Prove a read-only turn and a permitted worktree-writing turn in isolated
  workspaces; normalize public activity, outcomes and redacted logs.
- [ ] Add task/process identity, cancellation, clean environment, path policy,
  finite timeout and baseline adapter conformance checks.

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
- [ ] Add explicit Arena/Tabula inheritance and overrides without changing saved
  battle snapshots (alongside R040). Arena inheritance is implemented in R040a;
  Tabula inheritance is implemented in R040b. R030b adds confirmed adoption of the
  latest saved default for either scope; per-scope role editing remains. See
  [task](../tasks/R030b-scoped-team-adoption.md) and
  [evidence](../worklog/2026-10-07-R030b-scoped-team-adoption.md).
- [ ] Add confirmed/audited execution slots and grants; prove independent sessions
  sharing one connection/model without inferring permission from role text.

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
- [ ] Add/rename/reorder columns and assign custom roles through versioned
  definitions. Enforce mandatory final Secutor review after all writing stages.
- [ ] Create/edit tasks manually and from a selected planning role using a brief,
  selected files or `docs/`; persist versioned specs, source references and
  acceptance criteria. R040b implements manual database drafts and criteria;
  R040e adds brief proposals and source-command provenance; R040f adds selected
  document snapshots; R040h validates per-task citation scope and proposed
  prerequisites. R040i adds file-backed accepted specs; custom planning-role selection
  and battle-time spec preparation remain.
- [x] R040g: select bounded same-board task prerequisites, reject cycles against
  the latest graph and retain dependency revisions without launching work. See
  [task](../tasks/R040g-task-prerequisites.md) and
  [evidence](../worklog/2026-10-07-R040g-task-prerequisites.md).
- [x] R040h: validate prerequisite-first proposal graphs and selected-snapshot
  citations; resolve imported prerequisites and preserve original source linkage.
  See [task](../tasks/R040h-proposal-links.md) and
  [evidence](../worklog/2026-10-07-R040h-proposal-links.md). Citation meaning and
  accepted-spec validation remain separate from reference validation.
- [ ] Persist project-approved check commands and grants separately from agent
  proposals. R040j implements saved declarations; actual grants/execution remain.
  Draft empty states and keyboard movement exist in R040b.
- [x] R040j: explicit check preview/consent, immutable Arena revisions, idempotent
  audited saves, stale/recovered editor refusal and no implied execution authority.
  See [task](../tasks/R040j-project-checks.md) and
  [evidence](../worklog/2026-10-08-R040j-project-checks.md).
- [x] R040i: preview/accept exact saved intent as private Markdown, bind task and
  prerequisite revisions, verify hashes and preserve historical artifacts after edits.
  Acceptance/ToDo/history/events commit together; uncertain writes never replay.
  See [task](../tasks/R040i-accepted-specifications.md) and
  [evidence](../worklog/2026-10-07-R040i-accepted-specifications.md).

Acceptance: create an Arena from an empty folder and one from existing docs;
decline Git initialization without mutation; generate usable tasks with citations;
custom columns cannot bypass review; planning creates no coding processes.

## R050 — First autonomous battle

Depends on R040. This is the first end-to-end product milestone.

- [ ] Implement one Start battle authorization for goal/spec, task membership,
  team, model, policy, base revision, check commands and cumulative limits.
- [ ] Give Summa Rudis a closed decision contract; host-validate/persist decisions
  and route every launch through common admission.
- [ ] Run Speculator → Implementor → Secutor with explicit spec/candidate/evidence
  handoff; return all review comments to Speculator before another implementation.
- [ ] Execute confirmed custom stages in order with their actual grants.
- [ ] Retain independent Secutor sessions; bind passes to exact criteria, Git
  heads and host-check receipts. Summa Rudis cannot override rejection.
- [ ] Integrate locally into a battle branch, run final checks and final Secutor
  assessment, then show a complete result with branch/spec/review/log links.
- [ ] Permit reviewed in-scope repairs/splits while preserving original criteria,
  task lineage, lifetime counters and authorization.

Acceptance: one Start completes a two-task dependency chain with a forced review
return and no ordinary human prompts. A forged/stale completion cannot advance
state. New unrelated tasks remain outside the running battle. No remote Git
operation or user-checkout merge occurs.

## R060 — Controls and durable recovery

Depends on R050.

- [ ] Implement Pause/Resume/Retry/Stop/Skip with durable intent, correct pending
  states, verified process cleanup and retained partial artifacts.
- [ ] Add bounded transient recovery/backoff, separate review/failure counters,
  deadline enforcement and no repeated sign-in questions per task.
- [ ] Reconcile DB/process/transport/worktree/Git/port ownership before startup
  admission; never blindly replay uncertain work.
- [ ] Detect sleep gaps, reconcile leases, preserve active/wall accounting and
  manage the native idle-sleep assertion honestly.
- [ ] Classify task-local versus Arena-wide blockers; continue independent work
  when safe and present the smallest actionable attention request.
- [ ] Preserve input/focus and reconnect both UI and workers safely.

Acceptance: crash before/after launch and integration, lost transport, rate-limit
wait, revoked auth, PID reuse and budget exhaustion produce correct durable
states without duplicate execution. Pass simulated and physical sleep/wake tests
separately. Stop preserves changes and cannot kill an unrelated provider app.

## R070 — Parallel workers and safe combined results

Depends on R060. Required for the requested release, not a deferred enhancement.

- [ ] Clone role instances into independent sessions/worktrees/process groups.
- [ ] Atomically claim tasks, capacity and ports; enforce global/Arena/Tabula/
  provider caps, fairness and one active battle per Arena.
- [ ] Dispatch independent tasks concurrently; wait for integrated prerequisites.
- [ ] Serialize integration; if the battle head changed, validate/test/review the
  combined candidate and compare-and-swap the head.
- [ ] Route conflicts to bounded spec/implementation repair; retain every branch
  and failed integration candidate.
- [ ] Recover uncertain Git effects and expired claims without duplicate work;
  reserve scheduling opportunity for coordinator/review to avoid starvation.

Acceptance: run two independent tasks concurrently, a third dependent task after
both, a deliberate overlap/conflict, two Arenas and a crash during integration.
No lost code, duplicate claims, stale review acceptance or premature Completed.

## R080 — Tabula Gladiatorum and ten-minute experience

Depends on R070; earlier slices already provide functional UI.

- [ ] Global dashboard: Arena summaries, active workers, progress and attention.
- [ ] Arena dashboard: selected Tabula, team/progress and worker details using the
  same durable projections.
- [ ] Task inspector: spec, review comments, attempts, candidates and evidence.
- [ ] Scrollable/paginated logs with follow-tail control and safe file opening.
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

- [ ] Claude Code: verify current official interface/license, safe authorization,
  model discovery/defaults, grant mapping, streaming, cancellation and recovery.
- [ ] Cursor: verify the same plus profile/history and project config behavior.
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

- [ ] Reproducible signed/notarized Apple Silicon application with bundled release
  and verified helper provenance; no developer toolchain needed by the user.
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
