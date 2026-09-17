# Worklog — 0301 Git worktree lifecycle and confinement

## Metadata

- Date/time (UTC): 2026-09-17T21:21:14Z
- Task: 0301
- Status: done
- Human/agent owner: Codex
- Branch: `feature/0301-git-worktree-lifecycle`
- Start revision: `e0c7d30`
- End revision: task commit
- Environment: Apple Silicon macOS 27.0, Erlang/OTP 28.4, Elixir/Mix 1.19.5

## Intended outcome

Create a host-side Git service that captures a trusted base revision, creates one unique branch and worktree per run below the configured workspace root, records base/head identity on the durable environment, reports status and drift, and rejects traversal or symlink escapes.

## Acceptance criteria restated

- Worktree paths remain inside the resolved workspace root and path traversal or symlink fixtures are rejected.
- Base and head SHAs are recorded on the run environment.
- Dirty base repositories and protected target branches are rejected.
- Drift is returned as a blocking status until a later user decision chooses how to proceed.
- Concurrent runs cannot share a branch or worktree.
- Integration coverage exercises the service against a local bare remote.

## Context inspected

- Required product, architecture, database, workflow, security, and execution-environment documents.
- Task 0301 and merged Phase 2 foundation at `e0c7d30`.
- Mandatory Ponytail full, local-runner, security-review, and quality-gates skills.
- Existing environment schema, startup reconciliation boundary, and XERJ reference-coding rules.

## Work performed

- Added a host-side Git service that captures a clean default-branch SHA, validates constrained branch names, rejects protected or existing branches, and creates a worktree from the recorded SHA with `/usr/bin/git` argument arrays rather than a shell.
- Added canonical path checks before and after creation, traversal-safe UUID path components, symlink-component rejection, an atomic ownership marker, and active worktree/run-directory uniqueness constraints.
- Recorded base and head SHAs on the environment and added read-only inspection for base, branch, head, clean status, and ownership-marker drift.
- Connected the Git inspector to the recovery boundary; the existing reconciler test contract now receives the environment record and a real drift integration check proves the run is durably blocked.
- Updated the execution, workflow, and database documentation with the implemented trust and ownership rules.

## Artifacts

- Commits/patches: task commit
- Migrations: `20260917213000_enforce_worktree_ownership.exs` (partial unique indexes; no row mutation)
- Logs/reports/screenshots: this worklog
- Configuration or policy hashes: unchanged

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| `rtk xerj search 'git worktree add remove base sha branch unique symlink canonical path confinement drift' -k 10 --prefix ref-vibe-kanban-v1` | pass | Retrieved the pinned worktree manager and Git CLI implementation before coding. |
| `rtk mix test test/cuckoding/execution/git_service_test.exs` | pass | 6 real-Git integration tests, 0 failures, using a disposable local bare remote. |
| `rtk mix test test/cuckoding/execution/git_service_test.exs test/cuckoding/reconciler_test.exs test/cuckoding/domain_test.exs` | pass | 2 properties and 16 tests, 0 failures; confinement, drift blocking, and schema constraints passed together. |
| Development migration preflight and `rtk mix ecto.migrate` | pass | No duplicate active worktree paths or run directories; both partial unique indexes applied without modifying rows. |
| `rtk mix quality` | pass | 8 properties and 48 tests, 0 failures; formatter, warnings-as-errors compile, strict Credo, Sobelow, and dependency audit passed. |
| `rtk git diff --check` | pass | No whitespace errors. |
| XERJ current-project refresh | pass | Final generation committed with every code file indexed. The temporary 99% flood-stage override required at 97% disk use was restored to `null` and verified. |

## Decisions and deviations

- Ponytail full 4.10.0 (MIT) selected the standard Git CLI and existing environment schema; no Git library, force-cleanup retry, or speculative runner abstraction was added.
- XERJ retrieved Vibe Kanban pinned revision `735654971bd396aa97b65166955678e4c34f8bf8` (Apache-2.0). Its worktree manager canonicalizes paths before metadata comparison at `crates/worktree-manager/src/worktree_manager.rs:189-216`, and its Git wrapper uses `git worktree add` argument arrays at `crates/git/src/cli.rs:84-105`. Cuckoding adapts those ideas with clean-base capture, strict ownership markers, no ambiguous cleanup, durable SHA records, and resume-blocking drift.
- Protected branch creation covers `main`, `master`, and the project's configured default branch. Existing branches are refused before creating a run directory; Git's ref lock remains the final concurrency guard within a repository.

## Risks and blockers

- Destructive cleanup is intentionally outside this task; task 0305 must prove marker and process ownership before removal.
- Static traversal and symlink escapes are covered before and after creation. A hostile same-user process can still race filesystem checks in the trusted-host model; task 1001 owns the adversarial race drill and the UI must not call this a sandbox.
- `GitRecoveryInspector` verifies worktrees now, but remains an explicit reconciler adapter until task 0302 supplies process and port inspection in the complete local inspector.

## Handoff

Task complete. Proceed to 0302 for host process groups, allowlisted environments, timeouts, and the composite local recovery inspector.

## Checklist

- [x] Task acceptance criteria reviewed.
- [x] Relevant documentation updated.
- [x] Tests and checks recorded honestly.
- [x] Secrets and sensitive content excluded/redacted.
- [x] Residual risks and skipped work are explicit.
- [x] Task status and next owner are updated.
