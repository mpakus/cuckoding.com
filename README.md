# Cuckoding · CC

A local-first macOS menubar app for AI-agent teamwork, with a minimal browser UI.
Set up your agents and roles once. For each **Arena** (project), the intended flow is:

**Add folder → Create tasks → Start**

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
Independent tasks may use parallel role instances with separate sessions/worktrees.
Git initialization asks first when needed. Local work is reviewed before completion;
remote push, user-branch merge and release remain separate human actions.

## What works today

**Local preview, 2026-10-15.** The first sequential Codex/Cursor Arena loop is implemented.
The complete product story still includes capabilities and release acceptance
listed below. Arena registration opens its default board; technical setup stays in Advanced.

| Available in the current code | Still to implement |
| --- | --- |
| Tray launch, authenticated browser and local SQLite state | Full timed ten-minute onboarding acceptance |
| Multiple named Codex/Cursor connections, model discovery and saved choices | Additional runtimes; Cursor initial planning |
| Saved agent/model assignments for Speculator, Implementor, Secutor and Summa Rudis | Real mixed-runtime battle acceptance |
| Folder registration with an automatic default board, direct Arena opening, Advanced setup and editable drafts | Custom columns and scoped role editing |
| Codex planning from a brief or bounded folder snapshots (`docs/` first), automatically saved task cards, prerequisites and original source citations | Real-account planning acceptance across supported runtimes |
| One bounded Start, sequential Codex/Cursor dispatch, correction through Speculator, independent Secutor review and retained local battle branch | Real-account end-to-end acceptance, general toolchain checks, recovery and parallel workers |

Agents uses `/agents`; Settings uses `/settings`. Agent setup follows
**Choose Agent → Connect and Authorize → Select models → Save**. Team assigns each
role independently: for example Cursor/Grok for Speculator and Codex/GPT for
Implementor, once those runtime capabilities are supported. Saving a binding is
not execution permission. A catalog is separate from model access.

Each agent has **Disconnect**. Confirming it signs out that private profile and
unassigns its roles in the current saved, Arena and board teams. Other agents and
historical teams remain intact. Finish/stop an unfinished battle before disconnecting
one of its agents. Reconnecting does not silently restore those assignments.
Saved roles remain usable when only the catalog's age changes; failed lookups,
sign-out and account/model/executable changes still need attention. New model
choices and optional access tests require a recent catalog.

**Create tasks**, **Repository setup** and **Add another board** open dialogs.
Use **+** beside Specs or ToDo to add a task manually. Advanced shows **Board team**
and **Use saved team**; version numbers are kept in Team history.

**Disconnect and unassign** also works if an agent's executable has changed or
is unavailable. Cuckoding disables that connection and clears its current roles
locally, without running the unverified program. The result states that provider
sign-out was not attempted; its private profile and history are retained. Other
saved connections stay separate. Verify/reconnect explicitly before reusing it.

Codex also has an optional **Execution isolation** diagnostic. With verified
`0.162.0-alpha.17.2`, it checks read-only/writing restrictions in two disposable
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
`0.162.0-alpha.17.2` or Cursor `2026.09.15-d2fe57e`.
Secutor reviews the checks described in every task and the combined result.
Missing required runtime/test evidence blocks completion; code inspection never
proves tests ran. **Advanced → Extra command checks (optional)** adds explicit
commands when needed; once configured, all must pass. Without them, no command
tests run and no passing command receipt is invented. Extra commands currently
require a Codex Implementor and support native system commands that run in one process;
Mix/npm pipelines and other subprocess toolchains are not supported.
**Pause** finishes the current stage and saves its result before holding the next
stage. **Resume** keeps the same team, work and limits; paused time counts toward
the original deadline. Clean paused battles survive restart. **Stop** cancels
and waits for cleanup. Interrupted work or uncertain effects require inspection;
there is no automatic replay. [Pause/Resume evidence](worklog/2026-10-14-R060a-battle-pause-resume.md).
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
The packaged build, smoke test and preserved-workspace relaunch were verified
2026-10-15; [build evidence](worklog/2026-10-15-R060e-late-stage-receipts.md).
**Retry failed stage** is available for settled transient provider failures in new
battles: two retries per task, plus two shared by final stages, within the same
time/turn limits. A failed Implementor returns through a fresh worktree and
Speculator; partial edits remain retained. Blocked reviews and uncertain effects
cannot be retried. [Retry evidence](worklog/2026-10-14-R060b-provider-retry.md).
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

R020n adds bounded Codex host file-tool turns, now used by R050e battle admission
and independent review. R020o fixes Codex tool routing;
a consented GPT-6.1 Sol fixture verified host read and hash-guarded edit, exact
final bytes and normal process cleanup. Full battle acceptance remains open.
R020p adds Cursor role execution with the same bounded host file operations.
It verifies the exact saved model variant, keeps native Cursor tools denied, and
routes each role to its assigned connection. A blocked Start now names the affected
roles and links directly to their agent setup. Cursor initial planning remains
unsupported. Protocol fixtures and real model-selection preflights pass; live
Cursor read/edit/denial acceptance is still pending usage approval.
[Cursor execution evidence](worklog/2026-10-13-R020p-cursor-task-execution.md).

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
