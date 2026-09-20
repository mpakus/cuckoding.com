# Documentation Audit

## Current-flow audit — 2026-09-20

Source baseline: `72fac12` (`feat(agents): reuse provider sign-in and select models`).
Tasks 1015, 1018, and 1019 reconcile the product-flow documentation with the
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
   two accounts, paths, and MCP/config separation. They do not prove native
   refresh or concurrent authenticated Codex/Cursor execution. Do not close
   task 1018 until one login completes isolated runs in two projects, survives
   restart/refresh, and fails safely after provider revocation.
2. **Medium — shared-account lifecycle is incomplete.** The global Agents page,
   durable save/status events, LiveView refresh, compatible-root validation,
   and explicit legacy board/queued-run bindings are implemented. Per-project
   impact lists and confirmed revoke/delete controls remain absent. Existing
   running/completed snapshots are intentionally immutable.
3. **High — the launcher does not execute the accepted workflow branches.**
   `lib/cuckoding/workflows/definition.ex` defines Review returns, but
   `lib/cuckoding/walking_skeleton.ex` runs a fixed three-stage sequence and
   waits for human release approval. GuidedRun does not connect the finding
   evaluator to rerun scheduling. Local completion without release is also
   absent from this launch path. Domain evaluator tests are not evidence that
   the user can complete those paths from a board.
4. **Medium — workflow customization is narrower than the original design.**
   Custom roles can be saved, but the default delivery launcher resolves the
   three built-in roles. The board UI has no workflow picker, assignment editor,
   or budget editor. OpenCode and Custom Agent remain setup-only; Cursor retains
   run-owned task configuration. A saved connection does not imply execution
   support.
5. **Release gate — local implementation is not beta acceptance.** Automated
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
