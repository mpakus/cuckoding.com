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
- **Status:** Accepted
- **Context:** The user wants an installed app whose only native surface is a status-bar menu (Cuckoding, About, Settings, Quit), with the whole interface in the browser.
- **Decision:** Tauri 2 in tray-only mode with Accessory activation policy launches the bundled mix release and opens the browser with single-use tokens. Alternatives kept viable through the shell contract: Swift/AppKit shell; elixir-desktop taskbar icon. Burrito is not used for the app bundle.
- **Alternatives:** Full Tauri window (rejected: not wanted); elixir-desktop (wxWidgets bundling, fallback); Burrito (packaging only, no shell).
- **Consequences:** The Phoenix side owns everything, including secrets; the shell is replaceable.
- **Verification:** Task 0003 spike and Phase 9 packaging tests.

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

## ADR-017 — Claude Code and Codex are the launch adapters

- **Date:** 2026-09-17
- **Status:** Accepted
- **Context:** The MVP needs two real provider adapters while keeping product logic provider-neutral. Supporting four launch adapters would expand the first conformance and recovery surface without proving the walking skeleton.
- **Decision:** Claude Code and Codex must pass the launch conformance suite. Cursor Agent and OpenCode keep stable adapter contracts and test doubles but are not launch-supported until their suites pass.
- **Alternatives:** Launch all four adapters (rejected as excess MVP scope); launch one adapter (rejected because cross-provider orchestration is part of the product claim).
- **Consequences:** Phase 4 prioritizes tasks 0402 and 0403; documentation and UI must label the other adapters as unavailable or experimental.
- **Verification:** Tasks 0401 through 0405 and the Phase 10 release matrix.

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

## ADR template

### ADR-NNN — Title

- **Date:** YYYY-MM-DD
- **Status:** Proposed | Accepted | Superseded | Rejected
- **Context:** What forces the decision?
- **Decision:** What is chosen?
- **Alternatives:** What was considered?
- **Consequences:** What becomes easier, harder, or constrained?
- **Verification:** How will the decision be validated?
