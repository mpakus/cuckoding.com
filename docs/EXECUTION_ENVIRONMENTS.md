# Execution Environments

## Summary

The MVP runs every agent and every repository command on the host, as the current user, through `LocalProcessRunner`. Isolation between runs comes from Git worktrees, per-run folders, port allocations, and process groups. Isolation from the rest of the machine comes only from Cuckoding's path/command policy and from the runtime's own permission system. This is a trusted-host model, not a sandbox, and the UI says so.

Container isolation is a `RunnerBridge` plugin family added later (Docker, OrbStack, Colima, Apple Containers). Nothing in the domain layer may assume either runner.

## RunnerBridge contract

| Operation | LocalProcessRunner behavior |
| --- | --- |
| `prepare` | Validate policy snapshot; create worktree under the workspace root; allocate ports; write generated agent configuration files inside the run folder |
| `start` | Launch the agent process in a new process group with a scrubbed environment; record PID, start identity, and ports |
| `exec` | Run a declared project command (bootstrap, test, lint, dev server) in the worktree, in its own process group, with timeout and output limits |
| `pause` | Ask the adapter for a checkpoint; keep processes alive |
| `hibernate` | Checkpoint, stop processes with the termination ladder, release ports and leases, keep the worktree |
| `resume` | Revalidate worktree and policy hashes, reallocate ports, restart services, resume or continue the session |
| `inspect` | Process tree, resource samples, port state, worktree status |
| `stream_events` | Normalized stdout/stderr/lifecycle events after redaction |
| `destroy` | Verify ownership, stop everything, remove worktree per retention |

## Workspace layout

```
<workspace_root>/
  <project_id>/
    <run_id>/
      worktree/        # git worktree checked out on the feature branch
      agent/           # generated, read-only runtime configuration for this run
      artifacts/       # specs, patches, reports, logs (content-addressed)
      run.json         # ownership marker: project/board/task/run IDs and policy hash
```

The workspace root defaults to `~/Library/Application Support/Cuckoding/workspaces` and is configurable per project. Worktrees are created from the trusted base SHA. The main repository's `.git` stays where the user keeps it; because everything runs on the host, worktree `gitdir` pointers work without special handling.

`Cuckoding.Execution.GitService` requires the registered repository to be clean, resolves the repository and workspace directories before comparing paths, and creates a new non-protected branch from the recorded default-branch SHA. Each run directory starts with an atomic `run.json` ownership marker and its environment records the same base and head SHA. Existing branches, existing run directories, traversal identifiers, and symlink components below the resolved workspace root are refused rather than cleaned automatically.

## Process supervision

- Every launched process gets its own session/process group (`setsid`). Because a runtime may create additional descendant groups, inspect and own the full process forest; signaling only the initial group is insufficient.
- Record PID plus start timestamp; verify both before signalling to avoid PID reuse.
- Startup and wake reconciliation use a read-only inspector. A numeric PID alone is never sufficient to continue, adopt, or signal a process; the observed start identity must match the durable record.
- Termination ladder: adapter graceful stop → signal owned descendant groups before the root group with `SIGINT` → `SIGTERM` → `SIGKILL`, each with a bounded wait and an event. Completion requires every observed PID and PGID to be gone.
- Bound stdout/stderr, apply redaction before persistence, and stream a public summary to the UI.
- Environment is built from an allowlist: `PATH` (resolved tool paths), `HOME`, locale, `PORT`/`CUCKODING_*`, and only the variables the policy declares. Never inherit the shell's full environment.

## Path and command policy

- The run may write only inside its worktree and run folder; `protected_paths` (for example `.cuckoding/`, `.github/workflows/`) are read-only for agents and changes to them are flagged for approval.
- Declared commands in `project.yml` are the only commands Cuckoding itself executes. The agent runtime executes its own commands under its own permission system; Cuckoding records the tool activity it can observe and does not claim to filter it.
- Resolve symlinks before confinement checks. Reject worktree roots outside the workspace root.
- Reject commands referencing paths outside the worktree in Cuckoding-executed commands.
- Reconciliation treats a missing worktree as recoverable only when no recorded process is still alive. Drift, an unverified canonical path, or a missing worktree with a live process blocks the run for human inspection.
- Git inspection is read-only: a changed default-branch SHA, checked-out branch, recorded head SHA, or ownership marker returns drift and blocks resume. It never rebases, resets, deletes, or accepts the new state without the later user decision.

## Preview ports and local URLs

- Each project declares an optional `commands.dev_server` and a `ports.range` (for example `4300-4399`).
- `prepare` allocates a free port from the range, passes it as `PORT` and `CUCKODING_PORT`, and records `preview_url` (`http://127.0.0.1:<port>`) on the environment row.
- The UI shows the preview link, health (probe on `/` or a declared `health_path`), and the worktree path with an "Open in Finder/editor" action.
- Ports are released on hibernate/stop and reallocated on resume; a run never reuses another active run's port.
- Reconciliation accepts a bound port only when its owner PID and start identity match one of the environment's durable process records. A free expected service port requests recovery; an unknown owner blocks the run.
- Optional later: a Cuckoding reverse proxy giving stable `http://127.0.0.1:<app>/preview/<run>/` paths.

## Resource accounting

- Sample CPU time, RSS, thread/process count, and open ports for every process group every 2–5 seconds while active.
- Aggregate to 1-minute and stage-level rollups; attribute to the agent session or command.
- Sustained breaches of per-run limits (declared in policy) generate events and may pause or hibernate the run. Hard enforcement of CPU/memory limits is not available on the host runner and is labeled as such.

## Concurrency limits

- Board and project concurrency limits cap active runs.
- A global limit on active agent sessions protects the machine and provider quotas.
- The scheduler checks free ports and memory headroom before starting a run.

## Honest limitations of the host runner

- No filesystem isolation beyond policy and the runtime's permission prompts.
- No network isolation or egress control.
- No hard CPU/memory limits.
- Malicious repository content can instruct an agent to act on the host; mitigations are the runtime's permission mode, protected paths, no secrets in environment, and human approval gates.
- Provider-specific config-directory switches may not redirect transcripts, workspace trust, plugins, or compatibility configuration. Each adapter must inventory actual child processes and global writes before it is enabled.

These limitations are shown in the project settings and in the run detail when the local runner is active.

## Future container runners

A container runner plugin implements `RunnerBridge` and declares in its manifest which isolation properties it provides (filesystem, network, resource limits, egress). The UI upgrades its isolation label from the manifest, never from assumptions. Candidate backends: Docker Desktop, OrbStack, Colima, Apple Containers. The plugin owns image policy, bind-mount confinement, and the `.git` visibility question (mount the worktree plus a read-only copy of the needed gitdir, or run Git host-side only).
