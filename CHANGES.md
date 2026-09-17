# Changes in v2

| Area | v1 | v2 | Why |
| --- | --- | --- | --- |
| Execution | Docker Compose sandbox per run | `LocalProcessRunner`: worktree folder, process group, port allocation, local preview URL. Container runners (Docker/OrbStack/Colima/Apple Containers) become `RunnerBridge` plugins, deferred | Docker on macOS was the biggest friction and the biggest source of unresolved design (agent location, worktree gitdir, egress claims). Honest trusted-host model first |
| Agent location | Ambiguous (process or container) | Agents run on the host as supervised child processes; isolation comes from Git worktrees, path/command policy, and the runtime's own permission system | Removes the contradiction and makes resume/auth work with runtime-native session files |
| Desktop shell | Tauri window + Phoenix sidecar | Menubar-only shell (Tauri 2 tray, Accessory policy) that launches the bundled release and opens the UI in the default browser. `docs/DESKTOP_SHELL.md` compares Tauri tray, Swift/AppKit, elixir-desktop, and Burrito | User requirement: UI in the browser, native surface limited to a status-bar menu |
| Long runs | Not addressed | `docs/LONG_RUNNING_AND_POWER.md`: power assertions, sleep/wake detection and reconciliation, unattended mode, checkpoint cadence | Runs of hours/days on a laptop must survive sleep |
| Optional tools | XERJ, RTK, Ponytail wired into core docs and MVP list | Plugin/connector system (`docs/PLUGINS.md`); XERJ/RTK/Ponytail are reference plugins detected on the machine | Core must not depend on small third-party tools; users bring their own |
| Knowledge | Compression pipeline with XERJ namespaces | Markdown-first knowledge store with SQLite index, per-run extraction, consolidation ("dream") jobs, evidence links, usage tracking, skill packaging. Landscape review in `docs/KNOWLEDGE_COMPRESSION.md` | Align with current agent-memory practice (Claude Code auto memory/Auto Dream, Mem0-style memory ops, Graphiti-style validity intervals, Agent Skills packaging) and make use visible |
| Dashboard | Fleet/board/run views | Adds Agent Floor (roles × agents live), Knowledge Growth, and Knowledge Lineage/Usage views | User requirement: see who does what and how knowledge accumulates and is used |
| Secrets | Keychain, ownership undefined | Phoenix process owns `SecretStore` (macOS Keychain via `security`/NIF); shell holds only the bootstrap token | Removes the Tauri/Phoenix boundary gap |
| Release stage | `release_preparer` agent role with GitHub token | Host-side system stage executed by Cuckoding's Git/VCS service after human approval; no provider token reaches an agent | Removes the token contradiction |
| Policies | Declared network classes that were not enforced | Only enforceable policy is declared as policy; advisory items are labeled `advisory` | Honesty rule applied to configuration |
| States | Task states in FLOW differed from workflow YAML | Single state vocabulary in `docs/FLOW.md`; YAML uses stage keys and transition labels only | Consistency |
| Plan | Infrastructure before value | Walking skeleton (0405) after adapters; packaging, plugins, and hardening after the product loop works | Earlier feedback |
| Tests | Generic | `docs/TESTING.md` expanded with per-component matrices, sleep/wake and long-run drills, plugin conformance, knowledge tests | User requirement |

Open items not decided in v2 (see `tasks/phase-00-discovery/0001`): product name, license, pricing hypothesis, Linux timing.
