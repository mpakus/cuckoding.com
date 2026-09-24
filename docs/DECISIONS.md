# Architecture Decision Log

This file records accepted product-level decisions. Add a dated ADR section when changing one. Do not edit old decision outcomes to make history look consistent.

## ADR-026 — Named agents share provider authorization independently of models

- **Status:** Accepted, 2026-09-20; extends ADR-025.
- **Decision:** A saved agent may reference a compatible root provider account for authorization. New agents reuse an existing compatible root by default, preferring an observed connected account; a separate account remains an explicit choice. Existing roots are preserved, not automatically merged. Models belong to each agent's settings and execution snapshots, not to authorization.
- **Boundary:** A nullable, indexed self-reference in `provider_accounts` preserves old profile paths. Only root references with the same runtime/executable/helper are allowed. References are immutable once saved; changing provider identity means adding an agent, not redirecting historical runs. Runtime checks and status resolve the root; tasks keep distinct instructions and model IDs.
- **Retention:** No application-imposed sign-out timer or token copying. Provider-native credential storage/refresh remains authoritative; revoked or non-refreshable sessions require reconnect. Years-long validity is not promised. Shared sign-in also shares provider history under ADR-025.

## ADR-027 — Bounded review returns and local completion

- **Date:** 2026-09-20
- **Status:** Accepted and implemented in task 1020.
- **Context:** The published default workflow routes Review findings back to Specifications or Coding, but the launcher currently runs each stage once and always requests release approval. Product flow also promises completion without publishing the branch.
- **Decision:** Review returns a closed, host-validated finding list. Error and blocker findings carry `fix_intent` or `fix_code`; the launcher persists them, chooses the earliest required stage, and reruns that stage plus its downstream stages. Three Review attempts is the fixed MVP budget. A passing Review waits for a human choice: release through the existing host-side handoff, or complete locally. Local completion rejects only the release handoff, cancels the waiting human stage, records the durable state transitions, and marks the run/task done without invoking a VCS host.
- **Alternatives:** Add a second workflow service (rejected because durable attempts and transitions already exist); let the reviewer execute arbitrary stage names (rejected because output is untrusted); treat local completion as release approval (rejected because it would blur the no-push boundary).
- **Consequences:** Timeline attempts and findings explain every return. Mixed findings restart from Specifications because Coding depends on accepted intent. Branch, worktree, and evidence remain available after local completion. Budget exhaustion blocks the run for human inspection.
- **Verification:** Structured-output validation, route/budget regression tests, no-handoff local-completion test, accessible LiveView control, transition/property/scheduler regression, and full quality gates.

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

**2026-09-19 implementation amendment:** The accepted wizard is now exactly
Project → Repository → Review. The Phoenix service opens the native folder
chooser; explicit final consent permits Git initialization/first commit for
empty or unborn repositories. Registration redirects to project settings for
saved agents and role assignments. Boards are created there with the default
workflow and copied roles; a workflow picker is not implemented. GuidedRun is
the live queued-run launcher, not test-only compatibility. ADR-024 adds the
global catalog; [CONFIGURATION.md](CONFIGURATION.md) defines snapshot behavior.
The accepted Review-return/local-complete flow remains a target: the current
launcher runs sequential stages then waits for release approval. The domain
definition's return transitions are not yet connected to rerun scheduling.
Task 1020 and ADR-027 later close this recorded gap.

## ADR-024 — Global agent catalog with credential-only authorization reuse

- **Date:** 2026-09-19
- **Status:** Accepted by the sole stakeholder
- **Context:** Project configuration already snapshots agent metadata for reproducible boards and runs, but saving the same machine-local runtime separately in every project and authenticating every run contradicts the reusable-agent product flow. Reusing an entire provider home would also share configuration, history, sessions, skills, and metadata across projects.
- **Decision:** `provider_accounts` is the global machine-local agent catalog. Project configurations store a stable account ID plus an immutable copy of the non-secret runtime settings; boards and runs keep their existing snapshot chain. Codex uses its supported macOS Keychain credential store for one-time authorization while retaining a separate generated `CODEX_HOME` for every run. Claude's reviewed helper remains reusable. Cursor keeps run-owned authentication until credential-only reuse passes the same global-write and MCP-isolation verification as its adapter.
- **Alternatives:** Reuse one complete provider home (rejected because it shares project state); copy file-backed credential directories into every run (rejected because it duplicates plaintext tokens); replace snapshots with live account references (rejected because history would drift).
- **Consequences:** Users enter agent metadata once and attach saved agents to any project. Authorization state may change globally without rewriting historical snapshots, while executable paths and role settings remain explainable. Revoking a provider login blocks future launches using that account.
- **Verification:** Provider-account persistence and cross-project attachment tests; Codex keyring/run-home adapter tests; LiveView save, attach, and authorization-command tests; secret-canary and full quality gates.

**2026-09-19 evidence qualification:** The tests above demonstrate metadata and
configuration behavior, not successful shared authentication between the
account-owned login home and a different run-owned home. That real-provider
gate remains open. Authentication mode is looked up live from the account;
authorization status is a mutable projection without its own append-only event.
There is no global revoke/delete UI or automatic migration of legacy boards.
These are explicit follow-ups, not completed guarantees of this decision.

## ADR-025 — Agent-first authorization and connection-level readiness

- **Date:** 2026-09-19
- **Status:** Accepted shared-profile mechanism on 2026-09-20; implementation delivered, real-provider acceptance pending
- **Context:** The stakeholder rejects repeating sign-in per run and displaying the same saved agent once per role. ADR-024's catalog alone did not deliver reusable authentication.
- **Decision:** Add and authorize an agent once in machine-wide Agents management; projects select saved agents and assign roles. The stakeholder explicitly selected one app-owned profile per saved agent, including shared provider history. This supersedes ADR-024's credential-only default and the per-run login requirement in ADR-017/021 for saved accounts. Run start checks distinct connections automatically. See [the flow contract](AGENT_AUTHORIZATION_FLOW.md).
- **Consequences:** Never use a personal CLI home or copy tokens. Codex uses the same account home with saved execution config ignored and run-specific permission overrides/instructions. Cursor shares HOME and selects its native owner-only file credential store because an isolated HOME cannot resolve the macOS default keychain; task config directories remain run-owned and shared sandbox/MCP files are fixed and checked. Separate account IDs get separate profiles. Boards and queued runs have explicit audited binding actions; historical snapshots remain immutable. Provider-scoped disconnect is explicit, confirmed, and audited.
- **Verification:** Deterministic tests cover two-project paths, distinct-account grouping, revocation, per-run settings and legacy binding preservation. Actual token refresh, concurrent authenticated provider sessions and global-write/MCP acceptance remain release gates, not inferred from passing mock checks.

**2026-09-21 Codex credential-store correction:** A real isolated launch failed
because macOS could not find the default Keychain with the run-owned `HOME`,
although a status check from the personal shell had succeeded. Codex now uses
its documented file store in the private app-owned `CODEX_HOME`, matching the
approved shared-profile boundary. This does not migrate or read the old keyring
credential; the user must sign in once again. The provider-owned token file is
regular and owner-only or launch fails closed. Real two-project and adversarial
provider acceptance remains open.

## ADR-028 — Project execution is durable; workers are disposable

- **Date:** 2026-09-22
- **Status:** Accepted for implementation of task 1029; local auto-completion remains a separate stakeholder decision
- **Context:** The board admission planner exists, but no production owner repeatedly dispatches Ready tasks. Per-task preparation/start cannot provide the requested one-click project operation.
- **Decision:** Store one project execution projection with Start/Pause/Attention/Done, concurrency and blocker threshold in SQLite. A supervised periodic worker reads it and the existing scheduler; it is not authoritative. Preparation and launch continue through `ProjectWorkflow` and `GuidedRun`. A blocked task with a host-validated `blocker` finding counts once toward the threshold. The initial default is two project runs and one critical blocker. A passing Review still waits for the existing human local-completion or approved release choice; no automatic push, merge, publication, or capability expansion follows from Start.
- **Alternatives:** Browser-owned timer (lost on navigation), GenServer-only state (lost on restart), a second workflow engine (duplicates established gates), and automatic completion without an approved policy (rejected for this slice).
- **Consequences:** Project Start persists before any provider work, can resume after restart, and stops new admission on attention. Existing runs and worktrees remain intact. Host-runner confinement remains advisory. The UI must not call a project Done while Review approval or Draft/blocked tasks remain.
- **Verification:** Durable command/event tests, scheduler fairness and race tests, LiveView keyboard/reconnect tests, crash/restart recovery, and real-provider concurrency acceptance remain distinct gates.

## ADR-029 — RTK uses frozen policy and a verified shell boundary

- **Date:** 2026-09-24
- **Status:** Accepted for task 1044 by the stakeholder
- **Context:** Prompt guidance alone does not intercept agent commands; native PATH misses Homebrew RTK. Hook rewriting can accidentally grant permissions or load untrusted repository configuration.
- **Decision:** Reuse audited RTK activations and run plugin snapshots. Discover a supported executable in approved host locations once for plugins and agents. All roles receive common instructions; automatic hooks require pinned-runtime rewriting, native permission/trust and configuration-isolation evidence. Unsupported combinations visibly use instructions only. Apply application filtering after underlying command validation; never filter provider protocols, authentication or machine-readable Git checks. Never retry an already executed command to recover filtering.
- **Consequences:** Optimization is optional and fails open before execution. Run-owned state and disabled raw recall prevent duplicate unredacted logs. Existing event storage records observations without equating an RTK prefix with measured reduction. No personal runtime settings or automatic upgrades are permitted.
- **Verification:** Discovery, snapshot, adapter, hook isolation, permission, secret-canary, confinement and single-execution regressions; installed runtime smokes, native build and a managed run recorded separately.

## ADR template

### ADR-NNN — Title

- **Date:** YYYY-MM-DD
- **Status:** Proposed | Accepted | Superseded | Rejected
- **Context:** What forces the decision?
- **Decision:** What is chosen?
- **Alternatives:** What was considered?
- **Consequences:** What becomes easier, harder, or constrained?
- **Verification:** How will the decision be validated?
