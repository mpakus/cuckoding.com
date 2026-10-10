# Cuckoding · CC

A macOS menubar app for simple, autonomous AI-agent workflows. Open it in your
browser, authorize local agents, choose models and roles, create an **Arena**
(project) and **Tabula** (board), describe the work, then **Start battle**.

**Summa Rudis** coordinates. **Speculator** writes specs and tasks.
**Implementor** writes code. **Secutor** checks the result against the specs.
Independent tasks can run in parallel; review comments return to Speculator.
The global and Arena **Tabula Gladiatorum** show who is working, progress,
attention items and logs.

## Current state

**Local preview, 2026-10-10.** The tray shell, authenticated browser, SQLite
commands/events, tool discovery and agent setup work. **Agents** (`/agents`) lists
your named connections; **Settings** (`/settings`) shows workspace settings. Choose **Add agent** or **Edit**, then follow **Choose Agent → Connect and Authorize → Select models → Save**.
Add multiple Codex or Cursor connections, each with a separate private profile.
Cursor setup implements sign-in/out and account model discovery; real signed-in
catalog acceptance still needs a user-completed Cursor login. Cursor model
tests and planning/execution remain unavailable. Claude Code and Hermes remain
coming soon. Executable details and
an optional usage-confirmed model test are collapsed. Sign-in disappears while
connected; sign-out and refresh remain available. All models returned by the
selected runtime are offered, including additional entries. Save remembers your
choices for new Team assignments; existing role bindings remain unchanged.
The version-check, sign-in and refresh buttons explicitly authorize their named
operations, without repeated setup checkboxes. Model selections survive live
updates; stale forms and reviewed saves are rejected. A refresh clears optional
test consent. Catalog metadata is separate from model access and execution grants.
**Team** saves the four default
roles plus custom roles, per-role agent/model assignments and instructions in immutable
revisions. Existing Arenas and Tabulae can explicitly adopt a newer saved team;
previous requests and draft history stay unchanged. Drafts can remain unassigned; stale models are shown without silently
replacing them. Saving a team starts no agent and grants no execution permission.
**Arenas** adds a native folder chooser and confirmed local registration with a
frozen team revision. It records directory identity without modifying project files.
**Tabulae** adds multiple boards per Arena, inherited team roles, manual task
drafts, saved revision history and keyboard movement between Specs and ToDo.
Select up to sixteen prerequisite tasks on the same board; circular dependencies
are refused and each saved selection remains in history. This records planning
order without launching agents.
**Repository setup** inspects registered Arenas and can initialize a missing Git
repository after separate confirmation. An unborn repository can then preview
explicitly selected files (or an empty baseline) and create its first local commit
after fresh confirmation. Working files remain unchanged; existing indexes/history
are refused. **Isolated worktrees** can prepare a locked, detached checkout from
a freshly inspected commit after separate confirmation. Original staged/unsaved
files stay unchanged. Attempts retain their location and receipt; uncertain partial
work is preserved. **Inspect worktree** verifies retained ownership/registration
and compares index entries and raw tracked bytes, flagging extra files without
reading their contents. Results are dated observations; Git checkout transformations
can also report differences. Preparation/inspection grant no agent/check execution.
See [Git setup limits](docs/DEVELOPMENT.md).

**Ask Speculator** turns a typed brief and optional selected document snapshots
into up to six proposals using the Tabula's
saved Codex/model binding and separate usage consent. Review each suggestion and
add it to Specs once, then edit it like any draft. This turn has no tools or project
file access. **Preview documents** reads up to four explicit Arena-relative
`.md`/`.txt` files locally (4,096 bytes each, 12,000 total). Review exact text and
hashes, then separately consent to send those snapshots. Proposals and source
text survive reconnect/restart. Files are never crawled or implicitly uploaded.
New suggestions include prerequisites and citations to those exact snapshots.
Add prerequisite suggestions to Specs first; dependent imports retain their task
links. **Original proposal sources** in the task editor preserves cited text and
hashes after later edits. Check that each citation supports the suggestion; the
app validates reference scope, not semantic correctness.

On a saved task, **Accepted specifications → Preview specification** shows exact
Markdown with task/prerequisite revisions and original citations. Confirm to retain
a private `.md` file and move the task to ToDo. Download verifies its hash; later
task or prerequisite edits mark it historical. Arena files remain untouched.

**Arena → Project checks** saves named verification commands with literal arguments,
a relative directory and a timeout. Review the exact declarations and confirm to
create a revision; earlier versions remain available. Saving runs nothing.

**Tabula → Battle preview** brings together the assigned team, saved tasks,
prerequisites, verified accepted Markdown, declared checks and last Git observation.
It shows missing or outdated preparation and links to settings. Refresh after
changes; the preview grants no execution and starts no battle.

Real Codex `0.146.0` login start/cancel, signed-out inspection, a signed-in full
catalog fetch (six models for the observed client/profile) and restricted
configuration/thread preflight passed. R020g also verifies the desktop runtime
`0.162.0-alpha.2`: the same private profile returns ten models, including GPT-6.1 Sol,
GPT-6 Astra/Sol/Luna and GPT-5.6 Terra. The standalone 0.146.0 catalog is older;
refreshing that executable cannot manufacture the newer client's list.
R020h also verifies the updated desktop `0.162.0-alpha.17.2`, including a real
GPT-6.1 Sol diagnostic response through the packaged helper and browser, and fixes the adapter
rejecting informational warning/deprecation notices. End-to-end packaged evidence
is recorded in its worklog. Repository execution and broader provider acceptance
remain open.
Dependency scheduling, execution grants and autonomous
battles remain unimplemented. Registration alone does not validate Git; an explicit inspection
distinguishes missing, unborn and committed standalone repositories.
The product story above remains the target, not a shipped capability list.

Evidence: [Multiple agents](worklog/2026-10-10-R020i-multiple-agents.md),
[Agent wizard and model check](worklog/2026-10-10-R020h-agent-wizard.md),
[Connection state and desktop runtime](worklog/2026-10-09-R020g-codex-setup-state.md),
[Full model catalog](worklog/2026-10-08-R020f-full-model-catalog.md),
[Profile checkbox fix](worklog/2026-10-08-R020e-profile-checkboxes.md),
[Worktree inspection worklog](worklog/2026-10-08-R050c-worktree-inspection.md),
[Owned worktree worklog](worklog/2026-10-08-R050b-owned-worktree.md),
[Battle preview worklog](worklog/2026-10-08-R050a-battle-preview.md),
[Project checks worklog](worklog/2026-10-08-R040j-project-checks.md),
[Accepted specifications worklog](worklog/2026-10-07-R040i-accepted-specifications.md),
[Proposal links worklog](worklog/2026-10-07-R040h-proposal-links.md),
[Task prerequisites worklog](worklog/2026-10-07-R040g-task-prerequisites.md),
[Selected document planning worklog](worklog/2026-10-07-R040f-document-planning.md),
[Scoped team adoption worklog](worklog/2026-10-07-R030b-scoped-team-adoption.md),
[Brief planning worklog](worklog/2026-10-07-R040e-brief-planning.md),
[Initial commit worklog](worklog/2026-10-07-R040d-initial-commit.md),
[Git setup worklog](worklog/2026-10-07-R040c-arena-git-setup.md),
[Tabula drafts worklog](worklog/2026-10-07-R040b-tabula-drafts.md),
[Arena registration worklog](worklog/2026-10-07-R040a-arena-registration.md),
[saved-team worklog](worklog/2026-10-07-R030a-saved-team.md),
[Codex diagnostic worklog](worklog/2026-10-07-R020d-model-access-check.md).

Build with `rtk proxy bin/dev.build`, then open
`desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`. It opens your browser;
use the **C icon menu → Open Cuckoding** to return later. See [Development](docs/DEVELOPMENT.md)
for prerequisites, quality commands and data isolation. This is a local
development build, not a signed/notarized public release.

The agent wizard keeps **Next: Select models** visible on step 2. Once the account
is connected, you can continue even if its catalog needs another refresh. Step 3
offers **Refresh models**; selecting/reviewing/saving still needs a fresh list.

## Public site

The black-and-electric-green cybernetic Arena lives in [site/](site/index.html):
original chrome agents, an orbital Colosseum, a sword-and-morgenstern duel,
dancing Pan and robots, ending with melancholy humans who outsourced their joy.
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
| [Product](docs/PRODUCT.md) | Eight-step journey, names, scope and setup target |
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
