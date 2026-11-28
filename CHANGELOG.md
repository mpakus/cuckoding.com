# Changelog

## 0.1.0-rc.3 — 2026-11-28

First GitHub release candidate for macOS on Apple Silicon. BOSS runs a local dashboard and uses the coding CLIs installed on your Mac.

- Start from one committed Markdown brief. Autopilot creates dependent board cards and a final review of the complete brief. The live Minute Clock trial took all three cards to Done, with eight named project tests available to the final reviewer.
- Independent Codex reviewers can return a task for diagnosis and a fresh implementation attempt. Each published commit has its own approval and postcheck.
- The macOS archive includes the BEAM runtime and native guardian. The tag workflow checks the archive against the tested source commit, publishes release notes and includes SHA-256 checksums.

## 0.1.0-rc.2 — 2026-11-18

Local macOS beta. Use the [release guide](docs/RELEASE.md) to build or launch it.

- Persist six-CLI agent detection (`Codex`, `Claude Code`, `Cursor Agent`,
  `Hermes`, `Pi`, `OpenCode`), Terminal sign-in helpers, model/reasoning
  catalogs and authorized role bindings (`Reviewer`, `Implementer`, `Analytic`
  and custom roles).
- Run managed planning, implementation, stuck-question diagnosis, documentation
  intake and independent review across **Codex**, **Claude Code**, **Cursor
  Agent** and **OpenCode**, preserving pinned `reviewer`, `implementer` and
  `analytic` roles across explicit review, candidate, timeout, checkpoint and
  provider rate-limit retries in both Elixir and SQLite triggers, and routing
  mixed non-Codex `Implementer` + Codex `Analytic` `:resolve` stages through the
  pinned Codex catalog.
- Plan tasks from committed project documentation and run their dependency order
  through checks, independent review, publication and postchecks in Autopilot,
  with live Three.js pipeline telemetry and structured stage diagnostics.
- Repair merge conflicts, rejected merge reviews, up to two clean target advances
  during merge review, rewritten tips and a first failed postcheck under autonomy
  policy 1 without rolling back published commits.
- Release autonomy v1 managed unknown-cleanup quarantine after the owned worker
  exits so Autopilot can continue other tasks without inventing stage success.
- Keep shared provider/credit outages, Stop and uncertain process cleanup
  visible with agent-specific diagnostics on the board and halt dispatch when
  ownership or the provider is uncertain.
- Add **Prompt task control** on `/projects/:id` (`Boss.Projects.TaskPrompt`,
  `BossWeb.TaskPrompt`, `priv/task_prompt_schema.json`) so owners can create
  tasks, revise task specifications, leave task notes (`add_task_note`), or
  control task states and workflows via natural-language prompts using a
  selected `Agent` + `Model` (`Codex`, `Claude Code`, `Cursor Agent` or
  `OpenCode`) in read-only mode while enforcing BOSS's versioned command and
  reviewer gates.
- Rebuild `/agents` (`BossWeb.AgentsLive`) and per-project role management
  (`Boss.Projects.RoleBindings`, `BossWeb.ProjectRoles`): compact connected-agent
  cards with model checkboxes, pricing and `Subscription` vs `API` badges; a
  side `+ Connect agent` CLI authorization panel; multiple named
  `Agent + Model + Role` bindings across `Analytic`, `Implementer` and
  `Reviewer` (e.g. `Reviews:CursorGemini4Carbon`, `Reviews:CodexGPT6.2Astra`);
  per-project 3-role selection on `/projects/:id`; default `spec_only` Reviewer
  verification against task specifications (with optional CLI check command
  override); and append-only `task_entries` (`Boss.Tasks.Entries`) showing
  current task state plus collaborative agent/owner comments, spec enrichments
  and stage logs in the task drawer.
- Open directly on loopback (`127.0.0.1`) for local macOS desktop use without a
  terminal unlock-token prompt, while preserving `Host`, exact-port `Origin`,
  `SameSite=Strict`, CSRF and WebSocket `check_origin` protections; remove the
  marketing-only `Pause motion` checkbox from the desktop application footer
  while keeping OS `prefers-reduced-motion` synchronization.
- Update Ecto to 3.14.3 for CVE-2026-118391 and Plug to 1.20.4 for
  CVE-2026-120287.
- Keep multi-byte UTF-8 CLI diagnostics valid across 240 B / 4 KiB / 512 KiB
  truncation boundaries and classify exit-`0` `is_error` / `error` envelopes on
  `Claude Code`, `Cursor Agent` and `OpenCode` instead of reporting generic
  invalid JSON.

## 0.1.0-rc.1 — unreleased

Initial BOSS release candidate for local macOS use. This is a source and packaging
candidate; public distribution/signing and real-provider acceptance are separate
release gates tracked in [docs/RELEASE.md](docs/RELEASE.md).

- Register Git repositories and specs through native folder dialogs.
- Import Markdown into a persistent board with immutable source revisions,
  versioned commands, dependency readiness and saved execution evidence.
- Run Codex planning/implementation, explicit checks, bounded fixes and independent
  Codex or Claude review in retained worktrees.
- Integrate exact approved commits with postchecks; advanced targets require fresh
  merge/check/review evidence. Autopilot processes a frozen Backlog sequentially.
- Preserve history across restart, pause unstarted work and quarantine uncertain
  cleanup instead of automatically repeating interrupted commands.
- Assemble an OTP release containing ERTS, native guardian, static assets and
  migrations. Agent CLIs and Git remain user-installed runtime tools.
- Update Bandit to1.14.1 after the dependency audit identified advisories in1.13.1.
- License BOSS under Apache-2.0 and include its full text in release archives.
- Pin isolated OTP28.5.0.8/static OpenSSL3.5.9 source builds, preserve embedded
  native component notices and reject stale/mismatched release runtimes.

Linux task execution, public signing/notarization and complete recovery-boundary
acceptance remain open. See [docs/RECOVERY.md](docs/RECOVERY.md).
