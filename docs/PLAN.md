# Implementation Plan

The plan is organized as gated phases. Task files under `tasks/` provide the detailed implementation units. A phase is complete only when its outcomes are demonstrated and every exit checklist item is true. The walking skeleton at the end of Phase 4 is the first checkpoint where the product is judged before more infrastructure is built.

## Phase 0 — Discovery and feasibility

**Outcome:** agreed MVP boundary, competitive position, trusted-host threat model, and proof that one agent runtime, the menubar shell, and sleep/wake handling work on macOS Apple Silicon.

- [x] Record product boundaries, competitors, name/license/pricing hypotheses, and threat model.
- [x] Spike one agent runtime on the host in a worktree with permissions, cancel, and resume.
- [x] Spike the menubar shell launching a bundled release and opening the browser. Protocol, clean-account, browser-handoff, and shutdown checks pass.
- [x] Spike sleep/wake detection and power assertions. Simulated, software-sleep, AC lid-close, and battery recovery checks pass.
- [x] Record findings and revise decisions.
- [x] Audit the planning pack and establish RTK/XERJ reference coding.
- [x] Place repository skills/configuration at root and verify the local toolchain.

## Phase 1 — Phoenix foundation

**Outcome:** a testable Phoenix/LiveView application with SQLite, supervision, durable commands, and local developer tooling.

- [x] Create the Phoenix application and quality gates.
- [x] Configure SQLite durability and migrations.
- [x] Implement append-only events and durable command dispatch.
- [x] Add process registry, supervision, leases, and correlation IDs.

## Phase 2 — Domain and persistence

**Outcome:** projects, boards, tasks, workflows, runs, attempts, approvals, artifacts, events, and secrets survive restarts.

- [x] Implement schemas and domain commands.
- [x] Enforce versioned workflow and policy snapshots.
- [x] Implement idempotent transitions and event sequencing.
- [x] Implement startup reconciliation and recovery.
- [x] Implement Keychain-backed `SecretStore` and redaction.

## Phase 3 — Local workspaces and process runner

**Outcome:** confined worktrees, supervised host processes, ports and preview URLs, hibernate/resume, and power handling.

- [x] Git worktree lifecycle and path confinement.
- [x] `LocalProcessRunner` with process groups, environment allowlist, timeouts.
- [x] Command policy and protected paths.
- [x] Port allocation and preview URLs.
- [x] Pause, hibernate, resume, safe cleanup.
- [x] Power assertions and sleep/wake reconciliation.

## Phase 4 — Agent adapters and walking skeleton

**Outcome:** normalized adapters and one end-to-end thin slice.

- [x] Adapter behaviour, fake adapter, conformance suite.
- [x] Claude Code, Codex, and run-scoped Cursor Agent adapters.
- [x] Cursor Agent adapter and OpenCode stable stub.
- [x] Walking skeleton: fake CI plus an isolated real-Codex demo cover sleep/resume, approval UI, evidence, and local-bare-remote release.

## Phase 5 — Workflow engine and Kanban

**Outcome:** tasks move through configurable durable workflows across multiple boards.

- [x] Workflow validation and transition evaluation.
- [x] Accessible Kanban and task detail.
- [x] Multiple boards, dependencies, budgets, concurrency, unattended mode.
- [x] Gates, human approval, host-side release handoff.

## Phase 6 — Agent Floor and telemetry

**Outcome:** users see who is doing what, what it costs, and what happened during sleep.

- [x] Normalized activity stream.
- [x] Host resource metrics and rollups.
- [x] Usage and cost accounting with confidence labels.
- [x] Agent Floor, run detail, agent inspector.

## Phase 7 — Knowledge

**Outcome:** evidence becomes reviewed project and global knowledge and skills; use is visible.

- [x] Knowledge store, front matter, index sync.
- [x] Per-run extraction with memory operations.
- [x] Consolidation jobs and redaction.
- [x] Review queue, publication, skill packaging, revocation.
- [x] Injection into runtimes and usage tracking.
- [x] Knowledge Growth and Lineage/Usage views.

## Phase 8 — Plugin system

**Outcome:** optional tools connect through manifests without touching the core.

- [x] Manifest schema, discovery, registry, health, enablement.
- [x] Behaviours and conformance suites per kind.
- [x] Reference plugins: RTK, Ponytail, XERJ, generic MCP server.
- [x] Container runner plugin contract and stub.

## Phase 9 — Shell and packaging

**Outcome:** a signed, notarized, updateable macOS build with the menubar shell.

- [x] Menubar shell and handshake.
- [x] Release bundling, signing, notarization.
- [x] Updater, backups, migrations, rollback.
- [x] Login item and diagnostics bundle.

## Phase 10 — Hardening and beta

**Outcome:** the product withstands common threats and recovers predictably; controlled external testing.

- [x] Capability and secret hardening, adversarial prompt and plugin tests.
- [x] Crash, power-loss, and sleep recovery drills.
- [x] The `3246b3b` unsigned developer `.app` built and passed the sterile
  release verifier, including startup/authentication, crash cleanup, safe mode,
  and update/rollback checks on 2026-09-21. The subsequent test-only gate
  correction did not change app source. This is not
  a signed beta enrollment build or clean-Mac release acceptance.
- [x] Release artifact staging preserves the prior signed distribution if
  notarization, updater signing, or metadata generation fails; a completed
  candidate is promoted with the previous distribution retained for rollback.
  This script regression is not a fresh signed/notarized build.
- [x] Automatic resource-sample pruning now retains old measurements until a
  finished stage aggregate is durable, including after a simulated eight-day
  interruption.
- [x] Task 1004: completed-minute rollups catch up in bounded, durable batches
  after a simulated outage; raw samples wait for both minute and stage
  aggregates before pruning. Signed-build retention/consent still needs
  verification.
- [x] Task 1004: reconcile the current launch-adapter, credential-store,
  public-name/license, and output-retention disclosures with shipped source.
  Artifact retention policy and signed-build consent verification remain open.
- [x] Task 1004: publish a source-grounded operator guide and explicit no-go
  report covering support, onboarding, limits, privacy/data, backup, recovery,
  and troubleshooting. Release notes/artifacts and clean-Mac acceptance remain
  open in [RELEASE_READINESS.md](RELEASE_READINESS.md).
- [x] Task 1004: the official macOS release workflow now runs `mix quality`
  before signing/notary secrets are imported. The first manual CI run exposed
  two tests that assumed an installed Claude CLI; after fixing those fixtures,
  [run 35663188771](https://github.com/mpakus/cuckoding.com/actions/runs/35663188771)
  on `112473e` passed 288 tests/10 properties, lint, security scan, and audit.
  The value-free preflight then stopped before certificate import because five
  Apple certificate/notary secrets are absent. Signed-artifact acceptance is open.
- [x] Task 1004: rerun the official hosted release source gate on `e96882b`.
  [Run 35680103836](https://github.com/mpakus/cuckoding.com/actions/runs/35680103836)
  passed `mix quality` (289 tests, 10 properties, zero failures) before the
  value-free preflight again found the same five missing Apple secrets.
  Signing, notarization, updater packaging, and artifact upload were skipped.
- [x] Task 1004: replace two non-resolving release-action SHAs with verified
  upstream v1.24.1 setup-beam and v7.0.0 certificate-import commits. Both
  pinned setup actions executed in the manual job; certificate import remains
  untested because the preflight correctly stopped first.
- [x] Task 1004: update the release workflow's checkout pin to official
  Node 24-native v5.1.0. [Branch run 35681124404](https://github.com/mpakus/cuckoding.com/actions/runs/35681124404)
  executed that checkout and passed `mix quality` (289 tests, 10 properties);
  it still stopped before signing on the same five missing Apple secrets.
- [x] Task 1004: verify GitHub Actions `macos-15` targets Apple Silicon and add
  a value-free preflight for all required release secrets and update variables
  after source quality, before certificate import. Missing Apple credentials
  still block an actual signed candidate.
- [x] Task 1004: document the stakeholder credential handoff for CI, including
  Developer ID `.p12` export, Team API key versus local `notarytool` profile,
  and the distinction between issuer ID and Team ID. Provisioning the five
  missing secrets and accepting a signed CI artifact remain open.
- [x] Task 1004: disclose in Settings that an explicitly created diagnostics
  bundle stays local until the owner deletes it and is not uploaded by the app.
  Stakeholder artifact-retention approval and signed-build consent checks remain open.
- [x] Task 1004: re-run the unsigned developer build and full source gate.
  The concurrent event-sequence property's wait now covers the existing bounded
  SQLite retry window; a controlled 11-second lock still completed and the
  full gate passed. This is not signed-release or real-provider evidence.
- [x] Task 1004: sign the then-current `3246b3b` app's 26 Mach-O files with
  Developer ID, notarize it with the saved `Cuckoding` profile, staple the accepted ticket,
  pass Gatekeeper, and re-run the embedded release's sterile verifier. This
  local app drill is not a signed updater/release package or clean-Mac acceptance.
- [x] Task 1004: archive that stapled app, extract the ZIP on the same Mac,
  apply a quarantine attribute to the extracted copy, and recheck its ticket,
  strict signature, Gatekeeper acceptance, and embedded-release sterile suite.
  The ZIP has a recorded SHA-256; this is not a clean-Mac install or updater.
- [x] Task 1004: stage the checksum-matched ZIP for the separate QA macOS
  account. Its menubar/browser launch remains unobserved: the current user's
  signed shell would use live app data, and switching to `qa` needs an
  administrator or an interactive QA login.
- [x] Task 1004: build then-current `17d367a` source in an isolated checkout, pass
  the sterile bundled-release verifier, sign all 26 Mach-O files, notarize and
  staple the app, then verify a quarantined extraction of its post-staple ZIP.
  This is revision-specific same-Mac app evidence, not a complete signed updater,
  clean-Mac install, or enrollment release.
- [x] Task 1004: stage that checksum-matched `17d367a` ZIP for the existing `qa`
  macOS account without replacing the older staged copy. Its menubar/browser
  launch and data checks remain unobserved.
- [x] Task 1004: rebuild `a3ef7b1` with `bin/dev.build`, pass its sterile
  verifier, sign and notarize the app, then verify a quarantined extraction
  of its post-staple ZIP on the same Mac. Stage a checksum-matched copy for
  the existing `qa` account without replacing older candidates. This is not
  an updater, QA-account launch, or clean-Mac acceptance.
- [x] Task 1004: repeat the build, Developer ID signing, Apple notarization,
  quarantined post-staple ZIP checks, and embedded-release sterile drill for
  `6ebbd6c` after the runner fix. Stage a checksum-matched copy for `qa`
  without replacing earlier candidates. This remains same-Mac app evidence.
- [ ] Produce and verify a fresh signed/notarized enrollment build at the
  accepted beta revision. The `6ebbd6c` signed app and ZIP passed same-Mac
  checks, but `desktop/dist/` predates current main; the signed updater,
  complete release metadata, clean-Mac test, and CI Apple certificate/notary
  secrets remain open.
- [x] Task 1008: safe public-message boundary and actionable empty states across
  Phoenix UI surfaces; raw internal errors are excluded from browser alerts.
- [x] Complete the accepted project-first product flow:
  - [x] Global dashboard lists projects, health, resources, active work, and attention.
  - [x] Add-project wizard separates identity, repository/branch, and review; project settings versions multiple agents and role assignments.
  - [x] Project settings creates boards independently from project registration.
  - [x] Board task creation and run preparation use the default Specifications → Coding → Review workflow and copied board role assignments.
  - [x] Board prompts create planning runs; validated, user-selected proposals become Draft tasks.
  - [x] Task 1024: blocked or failed delivery tasks can prepare a distinct retry
    run without deleting the prior run, worktree, logs, or artifacts; failed
    preparation leaves the task Ready for recovery.
  - [x] Task 1025: completed delivery and planning processes ingest bounded,
    provider-reported usage into idempotent session records. Missing or malformed
    telemetry remains unavailable; historical runs require an explicit safe
    replay and real-provider accounting acceptance remains open.
  - [x] Saved machine-local agent metadata can be attached across projects without rewriting old board/run snapshots.
  - [x] Task 1020: host-validated Review findings rerun Specifications/Coding within a fixed budget; passing runs can complete locally without release or continue to approved handoff.
- [ ] Task 1018: complete real-provider acceptance of [agent-first authorization](AGENT_AUTHORIZATION_FLOW.md). Global management, shared profiles, automatic checks, grouped roles and explicit legacy bindings are implemented and regression-tested. Both Cursor and Codex keyring access fail with an isolated run `HOME`; their native app-owned file stores are now selected consistently for sign-in, check, model discovery, launch and logout. Authenticated cross-project runs remain required evidence.
- [x] Task 1018 preflight: on 2026-09-21 both installed CLIs reported
  authenticated under isolated, app-owned file profiles. This is CLI status
  evidence only; it does not close the real-provider execution gate above.
- [x] Task 1018 runner hardening: a real Cursor smoke exposed same-group worker processes left after CLI exit; exit-time cleanup now has a failing-before/fixed-after regression and audited signal events. The smoke reused one Cursor sign-in in two disposable repositories, but did not exercise the full board workflow. Detached-group ownership and Codex workflow execution remain open gates.
- [x] Task 1018 process inspection now fails closed when the host `ps` table
  is unavailable or malformed before signaling or reporting a live group.
  This does not resolve detached descendants or replace real-provider tests.
- [x] Task 1019: reuse a compatible provider sign-in across named agents by default; select each agent's model independently and preserve it in planning/workflow requests. Additive migration and regression checks preserve existing accounts. Provider-controlled expiry and real authenticated concurrency remain task 1018 gates.
- [ ] Verify one saved login across isolated runs in two projects for each supported runtime, including refresh/restart/revocation and concurrency; current configuration tests are not proof of credential reuse.
- [x] Complete shared-account revocation UX and per-project impact lists. The
  confirmed provider-scoped logout records value-free request/completion events, blocks new
  launches for linked agents, and preserves running work and historical snapshots.
- [ ] Dogfood and controlled beta.
- [ ] MVP release readiness.

Remaining gate order: confirm rotation of the previously exposed provider key;
finish real-provider and shared-account lifecycle evidence; run controlled beta;
then execute task 1004 against one frozen signed release candidate. Isolated
CLI sign-in status and automated tests never substitute for those execution,
participant, or release acceptance gates.

## Definition of done for MVP

The [current-flow audit](DOCUMENTATION_AUDIT.md) separates implemented UI/domain
surfaces from real-provider and release evidence. Custom workflow/board editors
and execution through OpenCode/Custom Agent are not shipped capabilities.

- [ ] Two supported agent runtimes complete the default workflow on the host runner.
- [ ] Two boards run concurrently without worktree, port, process, or event crossover.
- [ ] A running task survives hibernate, app quit, relaunch, and a real sleep/wake cycle with a single execution of each stage. Task 1002 passed 27/27 named recovery drills, including physical sleep, but those stage workers were fixtures; the integrated current-build task observation remains open.
- [ ] The Agent Floor attributes every action to a role, runtime, model, and run.
- [ ] Provider-reported and estimated costs are visually distinguishable; active and wall time are both shown.
- [ ] A failed QA gate returns structured findings to development.
- [ ] Human approval triggers a host-side release handoff that pushes a branch and creates a draft PR.
- [ ] A completed run yields knowledge candidates; consolidation and publication require the documented approvals; the next run records knowledge usage; both dashboard views render.
- [ ] RTK, XERJ, Ponytail, and a generic MCP plugin can be enabled, contribute labeled results, and be removed without breaking core.
- [ ] A clean supported Mac installs, starts from the menubar, executes a sample project, updates, and uninstalls safely.
