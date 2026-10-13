# Cuckoding · CC

A local-first macOS menubar app for AI-agent teamwork, with a minimal browser UI.
Set up your agents and roles once. For each **Arena** (project), the intended flow is:

**Add folder → Create tasks → Start**

1. **Add folder.** Choose an empty folder or an existing project. Cuckoding uses
   your saved team and creates the default **Tabula** (board) automatically.
2. **Create tasks.** Ask Speculator to analyze `docs/` and relevant project files,
   optionally add a brief, and create the cards directly on that board. Edit if needed.
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

**Local preview, 2026-10-13.** The flow above is the revised product target, not a
claim that autonomous execution is available. The Arena UI now opens a default
board after registration and keeps technical setup in Advanced.

| Available in the current code | Still to implement |
| --- | --- |
| Tray launch, authenticated browser and local SQLite state | Full timed ten-minute onboarding acceptance |
| Multiple named Codex/Cursor connections, model discovery and saved choices | Additional runtimes; Cursor inference/planning |
| Saved agent/model assignments for Speculator, Implementor, Secutor and Summa Rudis | Execution grants and real mixed-runtime battles |
| Folder registration with an automatic default board, direct Arena opening, Advanced setup and editable drafts | Custom columns and scoped role editing |
| Codex planning from a brief or bounded folder snapshots (`docs/` first), automatically saved task cards, prerequisites and original source citations | Real-account planning acceptance across supported runtimes |
| Git setup, accepted specification artifacts, check declarations and isolated worktree preparation/inspection | One Start, automatic dispatch/card movement, independent review and local completion |

Agents uses `/agents`; Settings uses `/settings`. Agent setup follows
**Choose Agent → Connect and Authorize → Select models → Save**. Team assigns each
role independently: for example Cursor/Grok for Speculator and Codex/GPT for
Implementor, once those runtime capabilities are supported. Saving a binding is
not execution permission. A catalog is separate from model access.

Use **Create tasks → Read project folder** to preview up to 16 eligible text/source
files (16 KiB each, 64 KiB total), then confirm sending them to Speculator.
A brief is optional with sources; empty folders need one. The preview reports
excluded files and limits. Agents and Team keep their existing setup controls.
Press **Create tasks** to save up to six validated cards in Specs automatically.
Each keeps its prerequisites and source receipts; existing edits stay unchanged.
Older requests retain their individual **Add to Specs** controls. Start is still
unavailable. See
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

## UI development

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
