# Architecture Decision Log

This file records accepted product-level decisions. Add a dated ADR section when changing one. Do not edit old decision outcomes to make history look consistent.

## ADR-001 — Local-first desktop architecture (superseded by ADR-011)

- **Status:** Superseded
- **Decision:** Use a Tauri 2 native shell with a bundled Phoenix LiveView/Elixir control plane.

## ADR-002 — Phoenix LiveView is the main UI

- **Status:** Accepted
- **Decision:** Use LiveView and Tailwind in the default browser; the native surface is a menubar only.
- **Consequence:** High-frequency chart updates need batching; browser sessions need their own auth.

## ADR-003 — SQLite is the local source of truth

- **Status:** Accepted
- **Decision:** SQLite/Ecto with WAL, append-only events, projections; knowledge content in Markdown files indexed by SQLite.
- **Consequence:** Implement durable commands and leases in the domain layer; keep file/index consistency checks.

## ADR-004 — Durable hub-mediated workflows

- **Status:** Accepted
- **Decision:** Agent communication, handoffs, artifacts, and transitions go through the control plane.

## ADR-005 — Worktree plus Compose isolation (superseded by ADR-012)

- **Status:** Superseded

## ADR-006 — Explicit adapters and runner behaviour

- **Status:** Accepted
- **Decision:** Provider runtimes implement `AgentAdapter`; execution locations implement `RunnerBridge`.

## ADR-007 — Human approval at trust boundaries

- **Status:** Accepted

## ADR-008 — XERJ behind a knowledge gateway (superseded by ADR-013)

- **Status:** Superseded

## ADR-009 — Optimization metrics remain distinct

- **Status:** Accepted

## ADR-010 — Knowledge publication is reviewed and reversible

- **Status:** Accepted, extended by ADR-014

## ADR-011 — Menubar-only shell, UI in the default browser

- **Date:** 2026-09-16
- **Status:** Accepted; confirmed by task 0003 on 2026-09-17
- **Context:** The user wants an installed app whose only native surface is a status-bar menu (Cuckoding, About, Settings, Quit), with the whole interface in the browser.
- **Decision:** Tauri 2 in tray-only mode with `LSUIElement` and Accessory activation policy launches the bundled mix release and opens the browser with single-use tokens. The shell passes a unique mode-0600 bootstrap file, waits for exact readiness JSON, disables Erlang distribution, and owns the child process group through a bounded shutdown ladder. Alternatives remain viable through the shell contract: Swift/AppKit shell; elixir-desktop taskbar icon. Burrito is not used for the app bundle.
- **Alternatives:** Full Tauri window (rejected: not wanted); elixir-desktop (wxWidgets bundling, fallback); Burrito (packaging only, no shell).
- **Consequences:** The Phoenix side owns product state; the shell retains only its in-memory control credential. The shell is replaceable. Developer ID signing, nested ERTS signing, BEAM JIT entitlements, notarization, stapling, and clean-Mac install remain Phase 9 gates.
- **Verification:** Task 0003 passed release, authentication, replay, crash, signal, process cleanup, loopback-only, and sterile-home checks. See `docs/MENUBAR_SHELL_SPIKE.md`. Phase 9 owns distribution signing and notarization.

## ADR-012 — Host process runner first; container runners as plugins

- **Date:** 2026-09-16
- **Status:** Accepted
- **Context:** Docker on macOS was the largest friction and left the agent-location and worktree-gitdir questions unresolved.
- **Decision:** Agents and commands run on the host via `LocalProcessRunner` with worktrees, process groups, ports, and policy. Container runners (Docker, OrbStack, Colima, Apple Containers) implement `RunnerBridge` as plugins later and declare their isolation claims.
- **Consequences:** No isolation claims beyond policy and runtime permissions; UI shows the limitation; Git works host-side without special handling.
- **Verification:** Task 0002 spike; Phase 3 tests; Phase 10 adversarial repository tests.

## ADR-013 — Plugin/connector system for optional tools

- **Date:** 2026-09-16
- **Status:** Accepted
- **Decision:** XERJ, RTK, Ponytail, MCP servers, container runners, metric sources, VCS hosts, and secret stores are plugins with manifests, detection, permissions, scoped enablement, health, and conformance tests. Core talks only to behaviours.
- **Consequences:** Reference plugins must be maintained; the core has fakes for every kind.

## ADR-014 — Markdown-first knowledge with indexed provenance and usage tracking

- **Date:** 2026-09-16
- **Status:** Accepted
- **Context:** Current practice (Claude Code auto memory and consolidation, approval-based memories, explicit memory operations, validity intervals, Agent Skills packaging) converged on readable files plus structured consolidation.
- **Decision:** Knowledge lives as Markdown with front matter; SQLite indexes items, candidates, jobs, and usage; extraction per run, consolidation when idle, human approval for global; injection via runtime-native files for the run only; semantic retrieval via plugins.
- **Consequences:** Users can read and edit knowledge; dashboards can show growth and use.

## ADR-015 — Release handoff is a system stage

- **Date:** 2026-09-16
- **Status:** Accepted
- **Decision:** Push and PR creation run as application code after human approval; no agent role holds GitHub credentials.

## ADR-016 — Long-running runs are first-class

- **Date:** 2026-09-16
- **Status:** Accepted
- **Decision:** Power assertions while work is active, sleep-gap detection from clock divergence, reconciliation before scheduling, active vs wall time, unattended mode up to approval gates.

## ADR-017 — Reviewed run-scoped CLIs are launch adapters

- **Date:** 2026-09-17
- **Status:** Accepted
- **Context:** The MVP needs multiple real provider adapters while keeping product logic provider-neutral. Each additional launch adapter must prove the same authentication, isolation, event, cancellation, and recovery boundaries.
- **Decision:** Claude Code, Codex, and Cursor Agent must pass the launch conformance suite. Cursor is eligible only with a run-owned `HOME`, Cursor/Claude config directories, separate scoped login, empty MCP configuration, and no project runtime/MCP/plugin overrides. OpenCode keeps a stable adapter contract and test double but is not launch-supported until its suite passes.
- **Alternatives:** Launch all four adapters (rejected as excess MVP scope); launch one adapter (rejected because cross-provider orchestration is part of the product claim).
- **Consequences:** Phase 4 delivered Claude Code and Codex first; task 1006 enables Cursor only through its stricter run-owned-home path. Documentation and UI keep OpenCode and Custom Agent setup-only.
- **Verification:** Tasks 0401 through 0405, task 1006, and the Phase 10 release matrix.

## ADR-018 — Public product name is deferred

- **Date:** 2026-09-17
- **Status:** Accepted
- **Context:** The current name has an avoidable negative English connotation, while unverified alternatives create trademark and domain risk.
- **Decision:** Keep `Cuckoding` as an internal codename. Choose the public name by 2026-10-01 after 3–5 user interviews and trademark/domain screening. Initial candidates are `Runstead`, `Branchyard`, and `Agent Harbor`; none is approved or claimed available.
- **Consequences:** Do not invest in public branding, domains, or signed-bundle identifiers under a new name before the review.
- **Verification:** Task 1003 interviews and task 0902 packaging identifiers.

## ADR-019 — Apache-2.0 open-core license hypothesis

- **Date:** 2026-09-17
- **Status:** Accepted
- **Context:** The local core and plugin contracts need broad adoption and an express patent grant, while future hosted/team modules may be commercial.
- **Decision:** The sole stakeholder approved Apache-2.0 for the local core and plugin contracts on 2026-09-17; separately distributed paid modules may remain proprietary.
- **Alternatives:** MIT (simpler but lacks an express patent grant); AGPL (stronger reciprocity but conflicts with the proposed plugin/open-core adoption path); fully proprietary (weakens trust and local ecosystem adoption).
- **Consequences:** Source boundaries and third-party notices must remain explicit.
- **Verification:** Root license file, dependency-license scan, and task 1004 release review.

## ADR-020 — Initial pricing is an interview hypothesis

- **Date:** 2026-09-17
- **Status:** Accepted
- **Context:** The product needs a testable commercial boundary without prematurely paywalling the local orchestration wedge.
- **Decision:** Test Community at $0, individual Pro at $20/month or $200/year, and post-MVP Teams at $40/user/month. Keep core local orchestration, basic adapters, and the plugin system useful for free.
- **Alternatives:** Usage-based pricing (rejected for the initial hypothesis because provider usage is already variable); paid-only local app (rejected because it weakens open-core adoption).
- **Consequences:** No billing implementation belongs in the MVP until interviews validate willingness to pay and the paid feature boundary.
- **Verification:** Task 1003 interviews and a dated pricing review by 2026-10-01.

## ADR-021 — Process-forest cancellation and measured provider isolation

- **Date:** 2026-09-17
- **Status:** Accepted
- **Context:** The host runtime spike observed Cursor Agent launch a sandbox shell in a process group separate from the CLI. Signaling only the root group temporarily orphaned that shell. Cursor also started a user-global Claude-compatible MCP process and wrote under `~/.cursor/projects` despite isolated config directories and an MCP deny rule.
- **Decision:** `LocalProcessRunner` owns and terminates the full observed process forest, signaling descendant groups before the root and verifying all PIDs/PGIDs are gone. Adapter availability requires measured config, state, plugin, and MCP isolation; configured deny rules are not treated as proof that a server did not start.
- **Consequences:** Task 1006 resolves Cursor's retained failure by removing the real home and requiring run-owned authentication; it does not reinterpret an MCP deny as server isolation. Runtime-reported grants and global writes remain first-class audit evidence.
- **Verification:** Task 0002 report and fixtures; task 0302 process-tree tests; task 0404 rejection evidence; task 1006 scoped-home adapter conformance.

## ADR-022 — Uptime divergence and supervised caffeinate for power handling

- **Date:** 2026-09-17
- **Status:** Accepted; simulated, assertion lifecycle, software-sleep, and AC/battery lid-close checks passed
- **Context:** ADR-016 requires sleep-gap detection and a power assertion but did not pin the macOS clocks or assertion owner. The task 0004 platform check found that macOS 27 `CLOCK_MONOTONIC` continues during sleep; `CLOCK_UPTIME_RAW` is the clock that stops. Wall time can change independently through synchronization or manual adjustment.
- **Decision:** Detect gaps from `CLOCK_MONOTONIC - CLOCK_UPTIME_RAW` divergence above one second. Use wall time only for UTC labels and reported wall duration. The MVP control plane supervises `caffeinate -i -w <beam_pid>`, stops it when no eligible work remains, and relies on `-w` for crash cleanup. Do not request `-s` by default because it applies only on AC. Keep direct IOKit assertion ownership as a later shell optimization, not an MVP dependency.
- **Alternatives:** Wall-minus-monotonic divergence (rejected because monotonic includes sleep on the supported macOS); direct `IOPMAssertionCreateWithName` in the shell (valid and requires no special privilege, but adds cross-process ownership and native lifecycle code without improving the MVP contract).
- **Consequences:** Clock sources are injected and named explicitly in tests. Reconciliation is idempotent by sleep-gap ID and runs before scheduling. The UI must distinguish idle-sleep prevention from forced sleep, lid close, and battery behavior.
- **Verification:** Task 0004 unit, live assertion, coordinated `pmset sleepnow`, AC lid-close survival, and battery missing-worker recovery evidence.

## ADR-023 — Project-first onboarding and reusable agent roles

- **Date:** 2026-09-18
- **Status:** Accepted by the sole stakeholder
- **Context:** The first beta UI placed project identity, repository selection, runtime configuration, first task creation, branch/worktree authorization, and run creation in one dashboard form. The stakeholder expects Cuckoding to open as a project and operations dashboard, with project setup, board setup, and task execution as distinct flows.
- **Decision:** `/` is the global project and operations dashboard. Add/edit project uses a wizard for identity, existing repository and branch, reusable machine-local agent connections, role definitions, and review. Completing it creates only a project and trusted configuration version. Boards separately choose a workflow and snapshot role assignments. Tasks separately start runs. The default board flow is Specifications → Coding → Review → Complete, with labeled Review returns to Specifications or Coding and optional approved release stages.
- **Alternatives:** Keep the all-in-one queued-run form (rejected because it hides durable product objects and makes onboarding destructive); make the board the top-level object (rejected because one repository needs several independent boards); store only live agent-profile references (rejected because later edits would make run history irreproducible).
- **Consequences:** The dashboard becomes useful before any run exists. Agent connections can be reused, while project, board, and run snapshots preserve history. Project registration may accept a dirty repository, but task start still requires a clean verified base. The Phase 4 guided-run path remains test-only compatibility until its callers are retired.
- **Verification:** Project onboarding tests prove that registration creates no board, task, run, environment, or worktree; LiveView tests cover the wizard and project-first dashboard; board and run snapshot tests cover later tranches.

## ADR template

### ADR-NNN — Title

- **Date:** YYYY-MM-DD
- **Status:** Proposed | Accepted | Superseded | Rejected
- **Context:** What forces the decision?
- **Decision:** What is chosen?
- **Alternatives:** What was considered?
- **Consequences:** What becomes easier, harder, or constrained?
- **Verification:** How will the decision be validated?
