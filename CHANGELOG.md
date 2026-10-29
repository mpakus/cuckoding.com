# Changelog

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

Linux task execution, public signing/notarization and complete recovery-boundary
acceptance remain open. See [docs/RECOVERY.md](docs/RECOVERY.md).
