# Execution Environments

## Summary

The MVP runs every agent and every repository command on the host, as the current user, through `LocalProcessRunner`. Isolation between runs comes from Git worktrees, per-run folders, port allocations, and process groups. Isolation from the rest of the machine comes only from Cuckoding's path/command policy and from the runtime's own permission system. This is a trusted-host model, not a sandbox, and the UI says so.

Container isolation is a `RunnerBridge` plugin family added later (Docker, OrbStack, Colima, Apple Containers). Its frozen stub contract is in `docs/CONTAINER_RUNNER_CONTRACT.md`; no container backend is selectable yet. Nothing in the domain layer may assume either runner.

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

- Every launched process gets its own process group. Because a runtime may create additional descendant groups, inspect and own the full process forest; signaling only the initial group is insufficient.
- Record PID plus start timestamp; verify both before signalling to avoid PID reuse.
- Startup and wake reconciliation use a read-only inspector. A numeric PID alone is never sufficient to continue, adopt, or signal a process; the observed start identity must match the durable record.
- Termination ladder: adapter graceful stop → signal owned descendant groups before the root group with `SIGINT` → `SIGTERM` → `SIGKILL`, each with a bounded wait and an event. Completion requires every observed PID and PGID to be gone.
- Bound stdout/stderr, apply redaction before persistence, and stream a public summary to the UI.
- Environment is built from an allowlist: `PATH` (resolved tool paths), `HOME`, locale, `PORT`/`CUCKODING_*`, and only the variables the policy declares. Never inherit the shell's full environment.

`Cuckoding.Execution.LocalProcessRunner` owns each Erlang port through a temporary supervised worker. The macOS port launcher creates the process group; a short `/usr/bin/ruby` argv-preserving shim delays `exec` long enough to record the leader's PID, PGID, and `ps` start identity. The runner snapshots descendant groups, signals child groups before the root group, records each attempted signal before sending it, and refuses to signal when the durable start identity differs. This is supervision, not sandboxing.

The child environment starts empty: Cuckoding removes every inherited key, supplies a fixed system `PATH`, a per-run `HOME`, locale/timezone defaults, explicit `CUCKODING_*` values, and only policy-allowlisted additions. Credential-shaped names are refused. macOS may add its own platform bookkeeping variables after launch; ambient application values are not copied.

Stdout and stderr are combined into one ordered stream. Redaction runs before a mode-`0600` artifact write. The in-memory/UI preview stops at the configured byte limit and emits a durable truncation event that points callers to the complete redacted artifact; truncation is never silent.

## Path and command policy

- The run may write only inside its worktree and run folder; `protected_paths` (for example `.cuckoding/`, `.github/workflows/`) are read-only for agents and changes to them are flagged for approval.
- Declared commands in `project.yml` are the only commands Cuckoding itself executes. The agent runtime executes its own commands under its own permission system; Cuckoding records the tool activity it can observe and does not claim to filter it.
- The project loader hashes a validated, non-symlinked version 2 file. Command strings are tokenized without a shell, resolved to an absolute executable, and passed as argv; undeclared names, shell executables, NUL bytes, and statically visible absolute or parent-traversal arguments fail closed.
- The protected-path scanner combines the frozen-base commit range with staged, unstaged, and untracked changes. It includes both sides of renames/copies, always protects `.cuckoding/`, and keys approval to the exact sorted path-set digest. Pending or rejected approval blocks QA; a broader later diff needs another decision.
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

The implemented allocator checks the OS with a temporary loopback listener, acquires an exclusive SQLite lease, checks the OS again, and then writes the port and exact `http://127.0.0.1:<port>` URL under the database's active-port uniqueness constraint. Concurrent Cuckoding allocations therefore cannot collide. An arbitrary development server cannot inherit the probe socket, so another same-user host process can still win the short bind race; health exposes the failure and cleanup or lease expiry recovers it.

The dev server is the immutable snapshot's declared `dev_server` command. Cuckoding injects `HOST=127.0.0.1`, `PORT`, and `CUCKODING_PORT`; the health probe accepts only a loopback HTTP URL and an origin-relative path, follows no redirects, and reports `Healthy`, `Unhealthy · HTTP <status>`, or `Unavailable`. Stop terminates the owned process group before releasing the port. Hibernate uses the same release with `hibernated` state; resume performs a new allocation rather than trusting the prior port.

The shared LiveView preview panel renders textual health, a guarded preview link, and keyboard-accessible Finder/editor buttons. The user-triggered opener re-reads the environment, requires the recorded worktree path, resolves its physical directory, and invokes `/usr/bin/open` with argv rather than a shell.

## Lifecycle and cleanup

`Cuckoding.Execution.Lifecycle` composes the runner operations; it does not make an in-memory process the workflow owner. Pause verifies every recorded live process and persists the adapter's public checkpoint before the task/run transition. Hibernate persists a fresh checkpoint before the termination ladder, then releases the port lease and preserves the worktree. A checkpoint failure leaves the processes and run state unchanged.

Resume reloads durable rows, accepts only a hibernated run, calls the read-only Git ownership/drift inspection, reallocates a port, and gives the adapter the same active attempt plus `checkpoint_json`. A failed resume releases the new allocation back to hibernated state. Cleanup stops owned processes, releases the port, and removes only a clean registered worktree whose canonical paths and `run.json` ownership fields still match. The run directory and artifacts are retained and enumerated; Cuckoding never force-removes a dirty or ambiguous path.

## Resource accounting

- Sample CPU time, RSS, thread/process count, and open ports for every process group every 2–5 seconds while active.
- Aggregate to 1-minute and stage-level rollups; attribute to the agent session or command.
- Sustained breaches of per-run limits (declared in policy) generate events and may pause or hibernate the run. Hard enforcement of CPU/memory limits is not available on the host runner and is labeled as such.

## Concurrency limits

- Board and project concurrency limits cap active runs.
- A global limit on active agent sessions protects the machine and provider quotas.
- The scheduler checks free ports and memory headroom before starting a run.

The Phase 5 scheduler reads the global session cap from application configuration, each board limit from SQLite, and the project run limit plus per-run advisory memory ceiling from the latest trusted project configuration (`resources.per_project.max_active_runs` and `resources.per_run.memory_mb_ceiling`). Its macOS host probe counts only loopback ports that are both physically bindable and free of an active durable lease, and derives available memory from `vm_stat`. These checks are admission signals, not a claim of hard host resource isolation; `PortAllocator` still performs the authoritative lease-and-bind claim when a run starts.

## Honest limitations of the host runner

- No filesystem isolation beyond policy and the runtime's permission prompts.
- No network isolation or egress control.
- No hard CPU/memory limits.
- Malicious repository content can instruct an agent to act on the host; mitigations are the runtime's permission mode, protected paths, no secrets in environment, and human approval gates.
- Provider-specific config-directory switches may not redirect transcripts, workspace trust, plugins, or compatibility configuration. Cursor therefore combines its config switch with a run-owned `HOME` and `CLAUDE_CONFIG_DIR`, requires a separate scoped login, and rejects project runtime/MCP/plugin overrides. Each adapter must inventory actual child processes and global writes before it is enabled.

These limitations are shown in the project settings and in the run detail when the local runner is active.

## Future container runners

A container runner plugin implements `RunnerBridge` and declares in its manifest which isolation properties it provides (filesystem, network, resource limits, egress). The UI labels these as declared, never inferred. Candidate backends are Docker Desktop, OrbStack, Colima, and Apple Containers. The stable contract keeps Git host-side and confines mounts to the run worktree and run directory; see `docs/CONTAINER_RUNNER_CONTRACT.md`.
