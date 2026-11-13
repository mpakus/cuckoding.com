# Changelog

## 0.1.0-rc.2 — 2026-11-13

Local macOS beta. Use the [release guide](docs/RELEASE.md) to build or launch it.

- Persist six-CLI agent detection (`Codex`, `Claude Code`, `Cursor Agent`,
  `Hermes`, `Pi`, `OpenCode`), Terminal sign-in helpers, model/reasoning
  catalogs and authorized role bindings (`Reviewer`, `Implementer`, `Analytic`
  and custom roles).
- Run managed planning, implementation, stuck-question diagnosis, documentation
  intake and independent review across **Codex**, **Claude Code**, **Cursor
  Agent** and **OpenCode**, preserving pinned roles across explicit retries.
- Plan tasks from committed project documentation and run their dependency order
  through checks, independent review, publication and postchecks in Autopilot,
  with live Three.js pipeline telemetry and structured stage diagnostics.
- Repair merge conflicts, rejected merge reviews, a single target advance during
  merge review and a first failed postcheck under autonomy policy 1 without
  rolling back published commits.
- Keep shared provider/credit outages, Stop and uncertain process cleanup
  visible with agent-specific diagnostics on the board and halt dispatch when
  ownership or the provider is uncertain.
- Update Ecto to 3.14.3 for CVE-2026-118391.

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
