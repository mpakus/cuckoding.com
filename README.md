# Cuckoding · CCoding

A macOS menubar app for simple, autonomous AI-agent workflows. Open it in your
browser, authorize local agents, choose models and roles, create an **Arena**
(project) and **Tabula** (board), describe the work, then **Start battle**.

**Summa Rudis** coordinates. **Speculator** writes specs and tasks.
**Implementor** writes code. **Secutor** checks the result against the specs.
Independent tasks can run in parallel; review comments return to Speculator.
The global and Arena **Tabula Gladiatorum** show who is working, progress,
attention items and logs.

## Current state

**Local foundation + Codex readiness preview, 2026-10-06.** The tray shell,
authenticated browser UI, SQLite events/commands and metadata-only discovery
are implemented. Agents & roles now accepts a Codex executable and runs an
explicitly confirmed, cancellable version check. The observed baseline is
`0.146.0`; detection, compatibility and authorization remain separate.
Verification: 30 Elixir tests, 8 Rust tests, packaged smoke, prior-schema upgrade
and a real Codex version check through the browser.
Agent authorization, models, roles, Arenas and battles are next;
the product story above remains the target, not a shipped capability list.

Build with `rtk proxy bin/dev.build`, then open
`desktop/src-tauri/target/release/bundle/macos/CCoding.app`. It opens your browser;
use the **trident menu → Open CCoding** to return later. See [Development](docs/DEVELOPMENT.md)
for prerequisites, quality commands and data isolation. This is a local
development build, not a signed/notarized public release.

## Public site

The Roman robot-gladiator site lives in [site/](site/index.html): original
trident/code branding, robot banquets, Pan and satyrs dancing in the arena,
a scrollable workflow, layered parallax and reduced-motion
controls. Preview it with `rtk proxy python3 -m http.server 4387 --bind 127.0.0.1
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
