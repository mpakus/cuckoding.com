# Documentation Audit

## Active full-flow implementation — task 1038

Task 1037 is integrated into local main at `5fa55bc`. Task 1038 now adds canonical
new role defaults, both correction routes through Speculator, immutable default
workflow version upgrades for new boards, and task-description/latest-spec
handoff. The audit found that earlier delivery prompts omitted descriptions and
did not pass the saved spec to Implementor/Reviewer; focused regressions now
cover that path and revision comments. Full quality passed 10 properties and
316 tests for the delivery-handoff slice merged at `00ce3db`. Existing boards
retain their snapshots. The next source slice adds another-model proposal review
with validated revisions, comments, a Markdown report and preserved history;
eight focused intake tests and full quality (10 properties, 319 tests) pass.
Proposal review was merged at `ca198ec`. Explicit automatic local completion
now records the choice at run start, preserves evidence and separate remote
approval, and defaults existing project controls to manual mode. Full quality
passes 10 properties and 322 tests, including database-copy migration evidence.
The runner control foundation was merged at `35fde75` with 324 tests and 10
properties passing. Task/global controls now add durable admission, stage launch
coordination, pause/resume/stop UI and retained-worktree retries; 57 focused
workflow/planning/control regressions and full quality (10 properties, 329 tests)
pass. Custom role execution/permissions,
final rendered UI acceptance and a current native app remain open in
[task 1038](../tasks/phase-10-hardening-beta/1038-complete-board-flow.md).
The dated audit below describes the state before these implementation changes.

## Design, setup and role-contract audit — 2026-09-24

Compared recent user requests with source and task 1032–1037 worklogs. At this
inspection, main and the local origin/main tracking ref are `25c00d3`; the active
branch is `feature/1037-agent-path-discovery` with uncommitted discovery changes.
This is a focused documentation follow-up, not a new full-repository, provider,
native-release or deployment acceptance run. Older observations below retain
their dates and do not describe current process state.

| Request / description | Source-grounded result | Remaining boundary |
| --- | --- | --- |
| Operational dashboard | Per-project task states, latest 20 public events, latest 50 operations and 12 UTC minute buckets for sampled current agent sessions | Bounded observations, not historical totals or fabricated trends |
| Reference-inspired application design | Pearl/violet LiveView surfaces, rounded panels, original portal/robot and crystal WebPs, accessible navigation | Reference-image copy and habit features were not product requirements; original art is not a product screenshot |
| Matching GitHub Pages design | Separate native static site with original crew, workflow and knowledge art | Does not change the native application; local/main evidence does not prove deployed Pages |
| Classic and sarcastic Irony modes | All three site illustrations and related text switch; Irony is the HTML/no-JS, preload, social and storage-fallback default; saved Classic survives reload | Site-only preference; no operational behavior or release claims change |
| Automatic agent path discovery | Shared known-location metadata lookup, Codex Desktop bundle fallback, explicit rescan and manual path; host-only home hint with child-environment regression | Working tree only, not rebuilt into the installed app; found, supported and signed-in are separate checks |
| Stop copies and run one app | Task 1034 records one unsigned native shell/release after cleanup and data-preserving migration | A later stop/relaunch request did not establish new completion evidence; no runtime inventory or restart performed in this audit |
| Default roles and extensibility | Accepted Speculator → Implementor → Reviewer contract now documented, including prompt/Markdown specs and return comments through Cuckoding | Source still names Specifications/Coding/Review, allows direct Coding returns, and has no arbitrary-stage or role-permission editor |

The canonical design and mode contract is in [UI_DASHBOARD.md](UI_DASHBOARD.md);
discovery/search order is in [AGENT_AUTHORIZATION_FLOW.md](AGENT_AUTHORIZATION_FLOW.md#executable-discovery).
[PRODUCT.md](PRODUCT.md#default-roles-and-extensibility) and [FLOW.md](FLOW.md#intended-default-feature-flow)
define the newly accepted role behavior; [PLAN.md](PLAN.md#role-contract-alignment--2026-09-24)
keeps its implementation and permission tests unchecked. Role names do not alter
stable IDs, historical snapshots, trusted grants or human release approval.

Evidence: [1032 dashboard](../worklog/2026-09-23-1032-home-operations-dashboard.md),
[1033 charts](../worklog/2026-09-23-1033-project-state-and-agent-chart.md),
[1034 application](../worklog/2026-09-24-1034-pearl-workspace.md),
[1035 Pages](../worklog/2026-09-24-1035-pearl-pages.md),
[1036 modes](../worklog/2026-09-24-1036-pages-irony-mode.md), and
[1037 discovery and documentation](../worklog/2026-09-24-1037-agent-path-discovery.md).
The updated contributor rules require safe process metadata inspection without
raw argv/environment dumps and distinguish source, main, remote, deployment,
packaged and running-build evidence. [RELEASE_READINESS.md](RELEASE_READINESS.md)
retains the no-go decision; no real-provider or clean-Mac gate is closed here.

Also corrected stale rotation blockers in PLAN and RELEASE_READINESS: the
specific earlier provider-key rotation was already stakeholder-confirmed on
2026-09-23 in [BETA_REPORT.md](BETA_REPORT.md) and commit `5d2d532`. This is the
existing attestation, not fresh secret inspection or blanket credential safety.

## Local dogfood addendum — 2026-09-23

The current source has board-level saved-agent assignment and project-level
automatic admission of Ready delivery tasks; the 2026-09-20 journey below is a
dated baseline, not the current operating path. Project settings can apply
saved roles to an existing board, and Start project admits eligible Ready tasks
up to the configured limits. Draft tasks, blocked runs, human review decisions,
release approval, and policy changes are not silently advanced. See
[AUTONOMOUS_PROJECT_FLOW.md](AUTONOMOUS_PROJECT_FLOW.md) for the implemented
boundary and remaining decisions.

In local dogfood, one Coding run was blocked by an application-supplied
five-minute timeout instead of its snapshotted one-hour stage budget. Two other
runs reached Review, but the Codex request was rejected before model work
because the nested `findings[].evidence` schema was not closed. Both root
causes now have source fixes and focused regressions. Historical runs and
partially written worktrees remain unchanged; a new authorized run is still
needed for end-to-end acceptance. The target project's own Phase 0 source
validation gate also remains open, so automatic admission must not be
interpreted as permission to start its Phase 1 work.

## Release-disclosure addendum — 2026-09-21

Task 1004 compared the MVP boundary against the runnable adapter list,
resource-pruning code, process-output artifacts, provider credential stores,
README, and repository `LICENSE`. Claude Code, Codex, and Cursor Agent have
implemented launch adapters, but real-provider workflow acceptance remains
open; OpenCode and Custom Agent remain setup-only. The previous 30-day
output/payload deletion and Keychain-only credential claims were inaccurate:
only resource metrics have automatic age pruning, full redacted process
artifacts have no age purge, and saved Codex/Cursor credentials live in
app-owned provider file profiles. `Cuckoding` is already the public working
name and Apache-2.0 `LICENSE` exists; final name and commercial-boundary
review remain open. [MVP_BOUNDARY_AND_POSITIONING.md](MVP_BOUNDARY_AND_POSITIONING.md),
[DB.md](DB.md), [BETA_REPORT.md](BETA_REPORT.md), and [PLAN.md](PLAN.md) now
separate those source facts from beta and signed-build acceptance. The
[release-readiness guide](RELEASE_READINESS.md) records the current no-go
decision and operator-facing limits.

## Current-flow audit — 2026-09-20

Source baseline before task 1020: `cb81c48` (`fix(ui): make messages safe and actionable`).
Tasks 1015, 1018, 1019, and 1020 reconcile the product-flow documentation with the
implemented agent-first catalog, explicit legacy bindings, shared provider
authorization, and independent model selection. This remains a source audit,
not authenticated provider, beta, or signed-release acceptance. The original
planning-pack audit is retained below as history.

### Implemented journey

| Step | Route / action | Source of truth |
| --- | --- | --- |
| Monitor projects | `/` | `lib/cuckoding_web/live/status_live.ex` |
| Register project | `/projects/new`: Project → Repository → Review; confirm Git initialization/first commit only when needed | `lib/cuckoding_web/live/project_setup_live.ex`, `lib/cuckoding/project_onboarding.ex` |
| Save agents | `/settings/agents`: save a runtime/model, authorize a root profile, reuse compatible sign-in status | `lib/cuckoding_web/live/agent_settings_live.ex`, `lib/cuckoding/agent_runtime.ex` |
| Configure project roles | `/projects/:id/edit`: attach saved agents, assign roles, save revision | `lib/cuckoding_web/live/project_edit_live.ex`, `lib/cuckoding/project_onboarding.ex` |
| Create board | Project settings: default workflow, name/description/concurrency, copied roles | `lib/cuckoding/project_workflow.ex` |
| Add work | `/boards/:id`: add Draft task or create a queued planning run | `lib/cuckoding_web/live/board_live.ex`, `lib/cuckoding/board_task_intake.ex` |
| Review planning | `/runs/:id`: authenticate/start analysis, inspect proposals, import selected Draft cards | `lib/cuckoding_web/live/run_live.ex`, `lib/cuckoding/board_task_intake.ex` |
| Execute task | `/boards/:board_id/tasks/:id`: mark Ready, Prepare run; run page verifies authentication and starts workflow | `lib/cuckoding_web/live/task_live.ex`, `lib/cuckoding/guided_run.ex` |
| Monitor execution | `/runs/:id`, `/agents`, `/agents/:id`; durable state with LiveView refresh | `lib/cuckoding_web/live/run_live.ex`, `lib/cuckoding_web/live/agent_floor_live.ex` |
| Resolve Review | Blocking findings durably return to Specifications or Coding; a passing run links to the dashboard choice | `lib/cuckoding/walking_skeleton.ex`, `lib/cuckoding/workflows/definition.ex` |
| Complete | Dashboard Attention: confirm local completion without push, or separately review and approve release | `lib/cuckoding_web/live/status_live.ex`, `lib/cuckoding/walking_skeleton.ex` |

Planning and execution require a clean committed base. Registration does not.
A planning prompt can read committed `docs/` files with read-only inspection
commands; proposals are untrusted data until validated and manually imported.
Creating a run is not launching an agent. Queued work appears on the dashboard
before an agent session exists. Kanban columns are lifecycle states, not stages.

### Findings and remaining gates

1. **High — reusable provider authorization is implemented but not accepted
   against real providers.** Login, probe, grouped setup, and launch now resolve
   the same immutable root profile, and named agents may select independent
   models. Fixture tests cover restart-shaped reuse, revocation propagation,
   two accounts, paths, credential-store selection, and MCP/config separation.
   A real Cursor browser login exposed and fixed isolated-HOME Keychain failure,
   but does not yet prove persisted authentication, native refresh, or concurrent
   authenticated Codex/Cursor execution. Do not close
   task 1018 until one login completes isolated runs in two projects, survives
   restart/refresh, and fails safely after provider revocation.
2. **Resolved implementation gap — shared-account impact and disconnect.** The
   global Agents page lists every current project/board/role affected by a root
   sign-in and requires confirmation before provider-scoped logout. The durable
   disconnect event propagates authorization-required status to linked agents;
   running/completed snapshots remain immutable. Real authenticated revocation
   acceptance is still part of the high task-1018 gate above.
3. **Medium — workflow customization is narrower than the original design.**
   Custom roles can be saved, but the default delivery launcher resolves the
   three built-in roles. The board UI has no workflow picker, assignment editor,
   or budget editor. OpenCode and Custom Agent remain setup-only; Cursor retains
   run-owned task configuration. A saved connection does not imply execution
   support.
4. **Release gate — local implementation is not beta acceptance.** Automated
   quality gates and simulated recovery are implementation evidence, not the
   multi-day dogfood, 3–5 stakeholder-led interviews, real-provider concurrency,
   or clean-Mac signed release-candidate acceptance required by tasks 1003,
   1018, and 1004. Historical failed runs cannot retroactively acquire missing
   evidence.

### Documentation corrections

Aligned the wizard and folder picker, saved-account/project/board/run ownership,
planning permissions, task launch steps, routes, and LiveView boundaries.
Removed test-only claims about the current GuidedRun launcher and distinguished
shipped board controls from design targets. The implementation checkboxes in
[PLAN.md](PLAN.md) do not close the provider/beta gates. See
[UI_DASHBOARD.md](UI_DASHBOARD.md), [CONFIGURATION.md](CONFIGURATION.md),
[TESTING.md](TESTING.md), and [BETA_RUNBOOK.md](BETA_RUNBOOK.md) for the operational flow.

## Historical planning-pack audit — 2026-09-17

Audited on 2026-09-17 against the planning-pack working tree at `b101eee347e6b19d53209decd7504d1f61a94a85`. This is a documentation and configuration audit, not evidence that the product has been implemented.

## Scope and method

Every file in the original planning pack under `docs/` was inspected. Cross-references were checked against the root `README.md`, `AGENTS.md`, the original 49 numbered task files, and the worklog templates because those files define how the documentation is executed. Task 0006 subsequently added the 50th task and promoted the skill and configuration packs to their intended repository-root locations; task 0007 added the 51st task for mandatory engineering defaults.

| Class | Files | Current location | Result |
| --- | ---: | --- | --- |
| Core product, architecture, operations, security, audit, reference-coding, and readiness specifications | 23 | `docs/` | Read in full |
| Reference plugin specifications | 3 | `docs/plugins/` | Read in full |
| Repository skills | 13 | `.agents/skills/` | Read in full |
| Agent role prompts | 4 | `.cuckoding/agents/` | Read in full |
| YAML configuration examples | 5 | `.cuckoding/` | Parsed successfully |
| Reference-corpus manifest | 1 | `docs/` | Parsed successfully |
| Finder metadata | 2 | `docs/`, `.cuckoding/` | Excluded from content review; `.DS_Store` is not product documentation |

The 49 substantive files are readable and mutually reinforcing. The specifications consistently preserve the most important boundaries: SQLite is durable truth, events are persisted before broadcast, host execution is not described as a sandbox, secrets stay out of agent processes, release actions remain host-side and human-approved, project knowledge requires reviewed publication, and sleep gaps are reconciled separately from crashes.

## Findings

### Resolved — Pack paths now match the checkout

`README.md`, `AGENTS.md`, and `docs/SKILLS.md` describe `.agents/skills/` and `.cuckoding/` as repository-root directories. Task 0006 promoted the misplaced packs to those paths without retaining duplicate copies.

Verification requires all 13 skills and nine configuration/role artifacts to resolve at root, with no `docs/.agents/` or `docs/.cuckoding/` directory remaining.

### P1 — Generic GitHub MCP example is not reproducibly pinned

`.cuckoding/plugins/mcp-github-readonly/plugin.yml` invokes `npx -y @modelcontextprotocol/server-github` without an exact reviewed version or artifact digest. That permits upstream code to change between otherwise identical runs and conflicts with the pack's provenance and trusted-configuration model.

Do not enable this example until task 0803 selects a maintained implementation, pins an exact version and integrity evidence, declares external-network access, and proves the tool allowlist in conformance tests.

### P2 — XERJ search mode and transport needed precision

The previous XERJ plugin text called all retrieval semantic even though the current server defaults to lexical embeddings. It also declared `network: false` while using a loopback HTTP service. The plugin and reference-coding documents now distinguish lexical from neural retrieval and declare loopback-only transport. External network access remains prohibited for the local backend.

### P2 — Release handoff omitted its secret-store dependency

Task 0504 consumes `SecretStore` but originally depended only on 0503 and 0301. Its dependency list now includes 0204 so the credential boundary exists before host-side push and pull-request work.

### Resolved P2 — Recovery percentage was underspecified

`docs/RECOVERY_DRILLS.md` now fixes the denominator at 27 named observations,
keeps retries outside the denominator, requires every row to pass even if the
aggregate remains above 95%, and records automated, five-stage real-sleep, and
battery-clamshell evidence. The committed combined report is 27/27.

### P3 — Generated task prose needs cleanup

Forty-one task objectives end with a doubled period and most repeat the first scope sentence verbatim. This does not change requirements, so it was left as low-risk editorial debt instead of producing a broad mechanical diff.

### P3 — Supplementary visual has no provenance link

The repository-root `inspire.jpg` is a dark AI/automation landing-page reference image and is not referenced by the product or UI documents. It is outside `docs/`, but its intended use, source, and license should be recorded before any design is derived from it or the asset is distributed.

## Deferred decisions that are not contradictions

- Tauri versus the documented native-shell fallback remains a Phase 00 spike outcome.
- Container runners and remote workers remain post-MVP plugin boundaries; the host runner is intentionally not called a sandbox.
- Optional XERJ, RTK, Ponytail, and MCP integrations do not weaken core availability requirements.
- Exact provider costs, model capabilities, signing flow, and packaging commands are intentionally revalidated during their implementation tasks.

## Readiness conclusion

The pack is a strong implementation specification, but it is not yet an implementation repository. Structural preparation is complete and Phase 00 can proceed. Phase 1 must wait for the Phase 00 product, runtime, shell, and sleep/wake spike evidence described in `docs/IMPLEMENTATION_READINESS.md`. The unpinned MCP example must remain disabled until task 0803.
