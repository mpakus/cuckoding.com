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

**Local preview, 2026-10-07.** The tray shell, authenticated browser, SQLite
commands/events, tool discovery and Codex setup work. **Agents** provides
consented version/profile checks, managed ChatGPT sign-in/out, a cached model
catalog and a fixed model-access diagnostic. **Team** saves the four default
roles plus custom roles, Codex/model assignments and instructions in immutable
revisions. Drafts can remain unassigned; stale models are shown without silently
replacing them. Saving a team starts no agent and grants no execution permission.
**Arenas** adds a native folder chooser and confirmed local registration with a
frozen team revision. It records directory identity without modifying project files.
**Tabulae** adds multiple boards per Arena, inherited team roles, manual task
drafts, saved revision history and keyboard movement between Specs and ToDo.
**Repository setup** inspects registered Arenas and can initialize a missing Git
repository after separate confirmation. An unborn repository can then preview
explicitly selected files (or an empty baseline) and create its first local commit
after fresh confirmation. Working files remain unchanged; existing indexes/history
are refused. See [Git setup limits](docs/DEVELOPMENT.md).

**Ask Speculator** turns a typed brief into up to six proposals using the Tabula's
saved Codex/model binding and separate usage consent. Review each suggestion and
add it to Specs once, then edit it like any draft. This turn has no tools or project
file access; proposals and their source brief survive reconnect/restart.

Real Codex `0.146.0` login start/cancel, signed-out inspection and restricted
configuration/thread preflight passed. Successful model responses use fixtures;
human-completed login, real responses and repository execution remain open.
Planning from files, accepted Markdown specs, execution grants and autonomous
battles are next. Registration alone does not validate Git; an explicit inspection
distinguishes missing, unborn and committed standalone repositories.
The product story above remains the target, not a shipped capability list.

Evidence: [Brief planning worklog](worklog/2026-10-07-R040e-brief-planning.md),
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

## Public site

The Roman robot-gladiator site lives in [site/](site/index.html): original
C/furcina branding, a sword-and-morgenstern duel, robot banquets and dancing
Pan, ending with melancholy humans who outsourced their leisure. Each scene
has a separate background and two character layers, with scroll motion, pause
and reduced-motion controls. Preview it with `rtk proxy python3 -m http.server 4387 --bind 127.0.0.1
--directory site`. [Site documentation](docs/SITE.md) covers checks, artwork and
the prepared GitHub Pages workflow. This change is local; it has not been deployed.

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
