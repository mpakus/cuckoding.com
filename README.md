# Cuckoding · CC

A local-first macOS menubar app for AI-agent teamwork, with a minimal browser UI.
Set up your agents and roles once. For each **Arena** (project), the intended flow is:

**Add folder → Create tasks → Start**

First-time setup follows **Agents → Roles → Arena & Tabula → Create tasks → Start**.
Home remembers saved setup and links back to existing Arenas. Agent/model choices
are visible directly on the four role cards; names and instructions expand on demand.
The black/green interface keeps one next action prominent. On an Arena, **Board
team** previews current versus saved assignments before an explicit adoption.
Start keeps the execution scope compact and groups connection problems; full tasks,
team and limits stay in Inspect. The ten-minute target still needs a timed
real-account run.

If **Start** is unavailable, its notice identifies the missing choice. **Choose
model** opens the affected Team role and remembers your board. Select the model,
**Save team**, then **Review team for [board] → Use saved team**. The review opens
on that exact board; one labelled action confirms the change. Selecting an
agent alone is an incomplete draft, and Team now says so before/after saving.
Disconnect intentionally clears current role assignments; reconnect and choose
their models explicitly before reusing that team.

1. **Add folder.** Choose an empty folder or an existing project. Cuckoding uses
   your saved team and creates the default **Tabula** (board) automatically.
2. **Create tasks.** Open the dialog and ask Speculator to analyze `docs/` and relevant project files,
   optionally add a brief, and create cards with acceptance criteria and verification
   instructions directly on that board. No separate check setup is required. Edit if needed.
3. **Start.** One button runs the team. **Summa Rudis** coordinates dispatch,
   retries and card movement. **Implementor** writes code; **Secutor** judges the
   result against the spec and checks. Review findings return to **Speculator**
   for revision, then implementation continues automatically.

The Arena stays on one board with an optional task/log inspector. Global and
Arena **Tabula Gladiatorum** dashboards show activity, progress and attention.
Custom board stages stay in one scrollable row; focus the board and use arrow
keys to reach every column. Task dialogs retain unsaved text through live updates.
Independent tasks may use parallel role instances with separate sessions/worktrees.
Git initialization asks first when needed. Local work is reviewed before completion;
remote push, user-branch merge and release remain separate human actions.

## What works today

**Local preview source, 2026-10-23.** The Codex/Cursor Arena loop includes independent-task implementation waves.
Settings → Build details identifies the packaged build, source revision, local
changes and application-input digest. Source UI previews are labelled separately.
The build retains artifact hashes in a private receipt; signing/notarization and
release acceptance remain separate gates.
Restart can inspect a complete retained combined candidate and pause for Resume,
fresh configured checks and independent review. It never recombines or recreates
missing proof; broader recovery and real-account acceptance remain open.
This also fixes a format mismatch that prevented parallel results from combining.
The repeatable packaged recovery check uses fresh synthetic workspaces and real
native Git operations. It verifies the normal app's restart checkpoint and
missing-proof refusal without provider calls; this is separate from real-account
battle acceptance. See [packaged recovery checks](docs/TESTING.md).
Before upgrading a recognized existing schema, startup verifies a private
database copy and retains its dated receipt. Settings → Database copy details
shows its location and recorded hash. Failed copies stop migration. Provider
profiles, project folders and native artifacts are excluded; full restore/update
acceptance remains open. See [upgrade backups](docs/DEVELOPMENT.md#pre-migration-database-copies-r100c).
The complete product story still includes capabilities and release acceptance
listed below. Arena registration opens its default board; technical setup stays in Advanced.

| Available in the current code | Still to implement |
| --- | --- |
| Tray launch, authenticated browser and local SQLite state | Full timed ten-minute onboarding acceptance |
| Multiple named Codex/Cursor connections, model discovery and saved choices | Additional runtimes |
| Saved agent/model assignments for Speculator, Implementor, Secutor and Summa Rudis | Real mixed-runtime battle acceptance |
| Folder registration with an automatic default board, direct Arena opening, scoped team editing, versioned column names, ordered custom read/write stages and editable drafts | Real-provider custom-stage acceptance |
| Codex/Cursor planning from a brief or bounded folder snapshots (`docs/` first), automatically saved task cards, prerequisites and original source citations | Real-account planning acceptance across supported runtimes |
| One bounded Start, independent task pipelines in waves of up to two, serialized independent review/integration, declared offline npm/Mix checks and a retained local battle branch | Task-proposed checks, project dependencies/platform verification, real-account end-to-end acceptance, full recovery and real-provider parallel acceptance |
| Global setup/planning/battle activity, selected-board team/progress and paginated events globally/per Arena | Timed real-account setup and broader dashboard/release acceptance |

Tabula Gladiatorum shows up to 20 saved active setup/planning/battle records and
the latest Arena progress. Open **Board activity** on a Tabula for its own work,
progress and saved team; started battles retain their frozen bindings in Inspect.
Saved state and wall time do not prove process liveness. Activity offers 20-event
pages, Older/Newer and Pause updates/Follow latest. Reading stays fixed during
updates. [Dashboard evidence](worklog/2026-10-21-R080i-board-activity.md).

Open a task's **Execution history** to inspect its frozen specification, public
review feedback, exact agent/model, candidates, file-tool receipts and command
checks. Attempts are collapsible and paginated; **Earlier execution** keeps older
results available without replacing current draft text. Expired work is labelled
as retained evidence. **Download evidence · JSON** saves that execution's public
20-attempt page and frozen criteria, with a date and scope. Older pages keep their
cursor; the latest page reflects saved receipts when downloaded. Downloads require
an active session, are capped at 2 MiB and exclude private provider envelopes.
This view runs no agents. [Download evidence](tasks/R080j-evidence-download.md).

Agents uses `/agents`; Settings uses `/settings`. Agent setup follows
**Choose Agent → Connect and Authorize → Select models → Save**.

Create tasks uses Speculator by default. **Planning role** in that dialog can
choose another role from the board's saved team. The request keeps that role's
exact agent/model and instructions; changing it clears usage consent and keeps
your brief/sources. This planning choice does not change the team or battle stages.

In **Board team**, **Customize this board** opens the same role editor for only
that Tabula. **Save team here** changes its future planning/battles and keeps your
default team and other boards intact. **Customize this Arena** under Advanced
changes the team inherited by new boards. Existing work keeps its frozen team.
The saved-default editor and explicit **Use saved team** action remain available.
[Scoped team evidence](tasks/R030c-scoped-team-editor.md).

Extra custom roles are available for planning. Start always uses Speculator,
Implementor, Secutor and Summa Rudis; an unused custom role does not block the
battle or get execution access. Inspect lists unused planning roles separately.

**Advanced → Board columns** renames the five core columns and optionally adds
up to four custom stages before or after Implementor. Add each role with its
agent/model in this board's Team, then choose **Read only** or **Read and edit
files**, placement and order here before **Save workflow**. Read is the default.
Every writer produces a retained checkpoint; later roles verify it, preserving
all earlier file changes. Independent Secutor review follows all configured stages.
No custom stage can run commands or grant completion. The whole task retains the
64 changed-file limit and existing finite Start budgets. Active work blocks edits;
old battles keep their original workflow and grants. These local fixtures/native
checks still need real-account custom-stage acceptance.

Back up before upgrading. The current schema is eighteen: writer checkpoints from
seventeen remain intact, with an additional blocked-task admission guard. Older
bundles refuse the upgraded database before dispatch.

New agents start with an editable name and an executable path detected from known
install locations when available. Cursor's
normal connection needs no typed path: choose Cursor, Continue, then Sign in.
Sign in opens the provider tab from that same click; its in-place Continue button
is a fallback if the browser blocks/closes the tab. Refresh appears after sign-in.
Team assigns each role independently: for example Cursor/Grok for Speculator and Codex/GPT for
Implementor, once those runtime capabilities are supported. Saving a binding is
not execution permission. A catalog is separate from model access.

Each agent has **Disconnect**. Confirming it signs out that private profile and
unassigns its roles in the current saved, Arena and board teams. Other agents and
historical teams remain intact. Finish/stop an unfinished battle before disconnecting
one of its agents. Reconnecting does not silently restore those assignments.
Completed sign-out shows **Disconnected** and disables the Disconnect button;
**Edit** opens authorization to reconnect. Older successful sign-outs display
correctly without another provider call.
Saved roles remain usable when only the catalog's age changes; failed lookups,
sign-out and account/model/executable changes still need attention. New model
choices and optional access tests require a recent catalog.

**Create tasks**, **Repository setup** and **Add another board** open dialogs.
Use **+** beside Specs or ToDo to add a task manually. **Board team → Use saved team**
is available beside the board title; version numbers are kept in Team history.
Identical saved role definitions need no extra adoption, even if their version
numbers differ. Editing/saving Team never silently changes an existing board.

All 25 requested [Addy Osmani skills](https://github.com/addyosmani/agent-skills)
are installed locally; the UI, simplification and incremental implementation
guidance informed this flow. See [skill provenance and precedence](docs/SKILLS.md).

**Disconnect and unassign** also works if an agent's executable has changed or
is unavailable. Cuckoding disables that connection and clears its current roles
locally, without running the unverified program. The result states that provider
sign-out was not attempted; its private profile and history are retained. Other
saved connections stay separate. Verify/reconnect explicitly before reusing it.

To start completely fresh, quit Cuckoding and run:

```sh
rtk proxy bin/reset-agents --data-dir '/absolute/path/to/your/cuckoding/data'
```

Type `RESET` after checking the displayed directory. Despite its name, this resets
**all local app state**: agents/private profiles, roles, Arenas/project registrations,
boards, tasks, history and artifacts. It retains a private recoverable archive
beside the data directory and leaves your actual project folders untouched.
Reopen with that same data directory. See [reset and recovery](docs/DEVELOPMENT.md#reset-all-local-workspace-data)
for defaults, archived credentials, running-work refusal and restore details.

Codex also has an optional **Execution isolation** diagnostic. With verified
`0.162.0-alpha.17.2` or `0.163.0-alpha.11.2`, it checks read-only/writing restrictions in two disposable
folders without signing in or using a model. Results are saved per connection;
they are sandbox evidence, not permission to execute Arena tasks.

Use **Create tasks → Read project folder** to preview up to 16 eligible text/source
files (16 KiB each, 64 KiB total), then confirm sending them to Speculator.
A brief is optional with sources; empty folders need one. The preview reports
excluded files and limits. Agents and Team keep their existing setup controls.
Press **Create tasks** to save up to six validated cards in Specs automatically.
Each keeps its prerequisites and source receipts; existing edits stay unchanged.
Older requests retain their individual **Add to Specs** controls. **Start** freezes
the default board, task criteria/checks, four assigned Codex/Cursor roles, model bindings and limits:
20 tasks, three review returns per task, 200 role turns and two hours. A committed
Git source, valid saved model bindings and verified task runtimes are required: Codex
`0.162.0-alpha.17.2` / `0.163.0-alpha.11.2` or Cursor `2026.09.15-d2fe57e`.
The newer Codex cohort passed fresh-profile policy/thread and OS canaries without
inference. Additional native tool/daemon defaults are disabled explicitly. Real
account execution remains a separate acceptance gate. [Compatibility evidence](tasks/R020s-codex-compatibility.md).
Claude is planned with subscription sign-in after Anthropic approval; it remains
unavailable pending that approval and adapter verification.
Secutor reviews the checks described in every task and the combined result.
Missing required runtime/test evidence blocks completion; code inspection never
proves tests ran. **Advanced → Extra command checks (optional)** adds explicit
commands when needed; once configured, all must pass. Without them, no command
tests run and no passing command receipt is invented. New Starts whose saved
checks are entirely `npm`/`mix` use an isolated offline Linux VM for each exact
candidate. Start prepares pinned toolchains on first use and reuses only a
verified saved image; the UI explains that first-use download. Codex and Cursor
roles keep their assigned bindings. Checks, failed-test correction and independent
review run in the existing supervised Arena workers, with verified VM shutdown
required before advancement. [Arena check integration](tasks/R050p-arena-guest-checks.md).

These checks do not download project dependencies or reproduce macOS/browser
environments. Automatic task-proposed checks and failure-log delivery remain
unfinished. Native system checks retain the separate Codex single-process grant;
mixing system and guest checks in one saved list is refused. Historical Starts
keep their original grants. Interrupted checks and hard VM-owner loss need
inspection; missing cleanup proof never releases capacity. Native containment and
keeper evidence are recorded separately from real-provider/release acceptance.
[Execution limits](docs/EXECUTION_ENVIRONMENTS.md), [native keeper](tasks/R050o-native-check-keeper.md).
**Pause** finishes the current stage and saves its result before holding the next
stage. **Resume** keeps the same team, work and limits; paused time counts toward
the original deadline. Clean paused battles survive restart. **Stop** cancels
and waits for cleanup. Interrupted work or uncertain effects require inspection;
there is no automatic replay. [Pause/Resume evidence](worklog/2026-10-14-R060a-battle-pause-resume.md).
New battles can keep working on independent tasks when one task reports a verified
blocker or exhausts its review rounds. Current workers finish and cleanup verifies
first. The blocked task and its dependents stay unfinished; no task is silently
skipped. Shared failures stop the Arena. Pause and restart still require Resume.
Back up before upgrading to schema eighteen; older builds refuse it.
[Task-local attention](tasks/R060r-task-local-blockers.md).
**Retained capture after restart.** If capture finished before its response was
saved, Cuckoding reads its complete original evidence. One/two captures or a mixed
capture/preparation pair can become one Paused checkpoint after every proof passes.
Press Resume to continue with the same bindings, slots and budgets. Edits, capture
and provider turns are never repeated. Missing proof stays blocked; expired/fenced
observations allow Stop only. [Candidate recovery](tasks/R060o-candidate-recovery.md).
Codex overloads receive a short bounded automatic retry within the existing
two-retry allowance. A reported usage/session limit stops without retry; an
ambiguous HTTP 429 offers manual Retry after waiting. Error details stay private,
and agent/model choices never change automatically. [Failure handling](tasks/R060q-provider-failures.md).
If restart interrupts an agent turn beside capture/worktree preparation, Cuckoding
checks their retained closure receipts in order. Every claim must verify before
**Stop** becomes available. Lost work is not accepted and this pair cannot Resume,
Retry or Skip. Missing proof stays blocked. [Mixed closure](tasks/R060p-mixed-closure.md).

If the app restarts between fully recorded stages, it reopens the battle as
**Paused after restart**. Press **Resume** to continue from the saved stage with
the same remaining limits. Unfinished attempts and unknown cleanup still require
inspection. [Checkpoint evidence](worklog/2026-10-14-R060d-restart-checkpoints.md).
When a stage reports after its time limit, **Inspect** retains its result and edits
as expired evidence, without accepting completion. **Stop** can close that battle
once every worker's cleanup is verified. Unknown cleanup still blocks new work;
late results cannot Resume, Retry or Skip. [Deadline recovery](tasks/R060e-late-stage-receipts.md).
Workers now commit valid results before notifying their coordinator. A restart
after that commit retains completed setup or pauses the saved battle checkpoint;
it does not replay the finished stage. [Handoff recovery](tasks/R060f-durable-worker-handoff.md).

New battles can also reconcile a native integration whose complete receipt
survived restart before the app saved its result. Cuckoding verifies the retained
evidence without repeating Git changes, keeps the interrupted attempt and pauses
for Resume. Missing or changed evidence remains blocked; expired work cannot
advance. This is a narrow recovery case, not full crash/sleep recovery.
[Retained integration recovery](tasks/R060g-retained-integration.md).

New battles can also inspect a completed writer worktree whose result was lost
before SQLite saved it. Complete matching evidence reopens a clean, in-budget
checkpoint as Paused for explicit Resume; no checkout or agent turn is repeated.
Inspect keeps the dated result and original interrupted history. New two-worker
waves can verify both interrupted preparations, one read at a time, and pause
both next stages together only after both proofs pass within their original
limits. Failed or incomplete waves cannot advance one task alone. Other unfinished
native stages and physical sleep remain recovery gates.
[Preparation recovery](tasks/R060m-retained-preparation.md).
[Wave checkpoint](tasks/R060n-wave-preparation.md).

Native helpers now report bounded process-group cleanup explicitly before
publishing results. Failed or malformed cleanup cannot become successful work,
sign-in or cancellation proof. Public edits remain inspectable; uncertain Cursor
session stores remain private. This does not recover missing receipts or escaped
sessions. [Cleanup evidence](worklog/2026-10-21-R060k-provider-cleanup.md).

New runs also retain native provider closure evidence before returning task
results. After a lost reply and restart, Cuckoding can verify that evidence and
let you Stop the interrupted run safely. It preserves edits and history without
accepting or repeating the lost work. Missing evidence still needs inspection.
[Retained provider closure](tasks/R060l-retained-provider-closure.md).

New battles also detect timing gaps and clock changes. Clean work pauses for
Resume; active stages are cancelled and their receipts retained without advancing
tasks. Stop waits for verified cleanup. Deadlines and consumed limits stay intact.
This conservative guard is not physical sleep or process recovery.
[Timing-gap fence](tasks/R060h-timing-gap-fence.md).

The native app also requests idle-system sleep protection while new battles
perform bounded work. It releases protection at a paused/idle boundary, and its
15-second OS lease expires without renewal. **Settings** shows the last native
report and its age. The display can sleep; lid closure, forced sleep and low
battery can still interrupt work. This does not complete sleep recovery.
[Idle-sleep protection](tasks/R060i-idle-sleep-lease.md).
The 2026-10-21 packaged build passes strict ad-hoc bundle verification and fresh
workspace smoke, including the dashboard. A copy of the retained database upgrades
from eleven to fourteen migrations with saved records intact; its original data
and provider profiles stay untouched. Developer ID signing/notarization,
clean-machine installation and real-provider acceptance remain open.
[Current local build evidence](worklog/2026-10-21-R100a-local-beta-verification.md).
**Retry failed stage** is available for settled transient provider failures in new
battles: two retries per task, plus two shared by final stages, within the same
time/turn limits. A failed Implementor returns through a fresh worktree and
Speculator; partial edits remain retained. Blocked reviews and uncertain effects
cannot be retried. [Retry evidence](worklog/2026-10-14-R060b-provider-retry.md).
New Starts automatically wait 5/20 seconds before retrying known connection,
busy-profile, timeout or launch failures with verified cleanup. The wait is saved
in SQLite and can be cancelled; it consumes the same retry budget and original
deadline. Restart cancels the automatic wait and requires explicit Retry. Generic
provider errors remain manual. [Backoff evidence](worklog/2026-10-21-R060j-provider-backoff.md).
New v2 Starts also retry explicit Codex overload after 5–7/20–22 seconds, with
bounded jitter and the same limits. Usage/session exhaustion stops; ambiguous
HTTP 429 stays manual. [Typed failure evidence](tasks/R060q-provider-failures.md).
New Starts share two stage workers across Arenas. Within a board, up to two
independent tasks form an implementation wave, each with its own workspace and
fresh sessions. Shared agent connections take one turn at a time; overlap depends
on the saved bindings. Checks, Secutor review and integration run in order after
implementation. A changed head produces a combined candidate for fresh review;
conflicts return through Speculator and a new writer. Dependent tasks wait for
reviewed results. Pause/Stop cover both workers. Older saved battles retain their
sequential policy. [Wave implementation](tasks/R070d-parallel-waves.md).

In Team, **Additional worker (optional)** assigns a second named agent and model
for a required role. Save it for future work, using the normal explicit adoption
for an existing board. New Starts freeze these pairs: two independent tasks can
use different Implementors simultaneously. Each exact connection still takes one
turn at a time; leaving the extra empty shares the primary. No credentials are
cloned and an unavailable assigned worker is never substituted. Final review and
configured checks keep their primary binding. Real-account parallel acceptance
remains open. [Assigned workers](tasks/R070e-assigned-workers.md). The [shared receipt boundary](tasks/R070c-stage-receipts.md)
keeps every outcome bound to its frozen attempt.
**Skip task** confirms leaving a clean paused or settled blocked/failed task
unfinished and defers its dependents. Independent tasks continue from reviewed work;
paused battles stay paused until Resume. Edits and evidence remain available.
Final checks and review still apply, with a **Partial** result instead of Completed.
If all tasks are omitted before any complete, the battle stops without more inference.
[Skip evidence](worklog/2026-10-14-R060c-task-skip.md).
New Start uses the current original committed source and retains previous result
branches. Real-account battle acceptance is still open. See
[Development](docs/DEVELOPMENT.md) for how this build works and
[the prioritized implementation checklist](docs/PLAN.md#next-delivery-order--simple-arena)
for the remaining execution work. Historical source/provider evidence is linked from the plan;
fixture tests do not prove a working autonomous battle.

Build with `rtk proxy bin/dev.build`, then open
`desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`. Return through the
**C icon menu → Open Cuckoding**. This is a local development build, not a
notarized public release. [Build prerequisites and checks](docs/DEVELOPMENT.md).
Quit the old app before opening a rebuilt bundle. `CCoding.app` is obsolete;
the current app has separate **Arenas**, **Agents** and **Team** pages. For an
existing test workspace, use its **Open Cuckoding Test.command** launcher to retain
the same saved agents, models and roles. Opening the bundle directly uses the
default workspace, which may contain different data.

Dependency maintenance: R101 updates Decimal to 3.2.0, resolving
CVE-2026-97853. See [verification](worklog/2026-10-13-R101-decimal-security.md).
R102 updates Bandit to 1.13.1 and its required Thousand Island dependency to 1.6.0,
fixing the published HTTP authority and HTTP/2 send-deadline advisories. Quality
now checks current Hex advisories before application tasks, alongside the existing
audit. [Verification and limitations](worklog/2026-10-21-R102-bandit-security.md).
R103 updates native Tokio to patched 1.53.3 for RUSTSEC-2026-0386. Seven existing
transitive maintenance/platform warnings remain tracked for release review.
[Native dependency evidence](worklog/2026-10-24-R103-native-tokio.md).

R020n adds bounded Codex host file-tool turns, now used by R050e battle admission
and independent review. R020o fixes Codex tool routing;
a consented GPT-6.1 Sol fixture verified host read and hash-guarded edit, exact
final bytes and normal process cleanup. Full battle acceptance remains open.
R020p adds Cursor role execution with the same bounded host file operations.
It verifies the exact saved model variant, keeps native Cursor tools denied, and
routes each role to its assigned connection. A blocked Start now names the affected
roles and links directly to their agent setup. R020r also adds initial Create tasks
through the assigned Cursor Speculator, with a separate no-tools grant and the
same validated task/citation graph. Protocol fixtures and real model-selection preflights pass; live
Cursor read/edit/denial acceptance is still pending usage approval.
[Cursor execution evidence](worklog/2026-10-13-R020p-cursor-task-execution.md).
[Cursor planning evidence](worklog/2026-10-21-R020r-cursor-planning.md).

R050d1 captures exact task edits into retained application-owned Git candidates.
R050e integrates only reviewed candidates into `ccoding/battles/<UUID>` and
checks/reviews the combined result before completion. The original checkout and
branch stay intact. [Execution contract and limitations](docs/ARENA_LOOP.md).

## UI development

Agent setup, authorization, planning and battle stages run in supervised BEAM
tasks. GenServers coordinate messages and durable claims; SQLite owns progress.
All application screens use LiveView/HEEx with shared function and stateful
components. [OTP/LiveView audit](tasks/R012-otp-workers-components.md).

After building the native helper with `rtk proxy bin/dev.build`, run
`rtk proxy bin/dev.server` to open the source app at `http://127.0.0.1:4000`.
Phoenix live asset/code reload and HEEx source annotations are enabled in development.
The launcher uses separate `.ccoding/ui-dev/` data and stops with Ctrl-C. If it reports **already running**, use the existing browser
tab or stop that launcher before starting another; do not delete its lock file.
Shutdown retains your developer data and releases its listener/lock before reuse.
Tidewave has been removed. See [setup and checks](docs/DEVELOPMENT.md#ui-development).

## Public site

The black-and-electric-green cybernetic Arena lives in [site/](site/index.html):
original chrome agents, an orbital Colosseum, a sword-and-morgenstern duel,
dancing Pan and robots, ending with melancholy humans who outsourced their joy.
The artwork combines gothic cathedral architecture with sci-fi leather, harness
hardware, spikes and ornamental chains in non-explicit stage/club fashion.
The Arena crowd wears leather harnesses, studded collars and chrome cuffs.
Four scenes have independent background/character layers with scroll motion,
pause and reduced-motion controls. The site opens with a full-screen cyborg and
scroll-driven camera approach, followed by spacious editorial sections and a
full-width duel, inspired by the requested 1367 Studio reference. All artwork is
our own; [design and motion details](docs/SITE.md). The internal app shares the dark panels,
green accents and restrained command-deck styling. The C/furcina logo is retained
in green across web and native icons. [Artwork and prompts](docs/ARTWORK.md).

Preview with `rtk proxy python3 -m http.server 4387 --bind 127.0.0.1 --directory site`.
[Site documentation](docs/SITE.md) covers checks and GitHub Pages. Public copy
separates implemented setup/planning from autonomous battles still on the roadmap.
This redesign is local; it has not been deployed.

## Start here

| Read | Purpose |
| --- | --- |
| [Product](docs/PRODUCT.md) | Original story, simplified Arena, names and scope |
| [Flow](docs/FLOW.md) | Battle control, review, parallelism and completion |
| [Implementation checklist](docs/PLAN.md) | Ordered slices and acceptance gates |
| [UI](docs/UI_DASHBOARD.md) | Minimal, modern, mouse-friendly TUI aesthetic |
| [Architecture](docs/ARCHITECTURE.md) | Unchanged stack and state ownership |
| [Documentation audit](docs/DOCUMENTATION_AUDIT.md) | What was kept, merged and removed |
| [Contributor rules](AGENTS.md) | RTK, Ponytail and verification |

The stack remains Elixir/OTP, Phoenix LiveView + Tailwind, Ecto + SQLite,
Git worktrees, supervised host processes and a thin Tauri 2 tray shell.
Local execution uses runtime permissions; the host runner is not a sandbox.

Use RTK for every repository shell command and Ponytail in full mode.
Search with `rtk rg`; no indexing service is required.
