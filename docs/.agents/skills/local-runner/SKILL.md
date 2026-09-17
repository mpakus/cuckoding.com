---
name: local-runner
description: Implement worktrees, host process groups, ports, confinement, hibernate/resume, and power handling for LocalProcessRunner.
---

# Local Runner

- One worktree and run folder per run under the workspace root; resolve symlinks before confinement checks.
- Launch every process in its own process group; record PID plus start identity; kill by group with the termination ladder.
- Build the environment from the allowlist; never inherit the shell environment; no secrets in env or argv.
- Allocate ports from the project range; pass `PORT`/`CUCKODING_PORT`; record `preview_url`; release on hibernate.
- Hold a power assertion only while work is active; detect sleep gaps via monotonic/wall divergence; reconcile before scheduling.
- Never call the host runner a sandbox; surface limitations in the UI.

Before completion: run process-group cleanup tests, path traversal tests, port allocation tests, and a simulated sleep-gap test.
