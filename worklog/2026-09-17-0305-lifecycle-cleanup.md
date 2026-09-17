# Worklog — 0305 Pause, hibernate, resume, and safe cleanup

## Acceptance criteria

- Hibernate persists a safe checkpoint before stopping owned processes and releasing ports.
- Relaunch and resume reuse the existing stage attempt, after worktree and policy revalidation, and allocate a fresh port.
- Cleanup proves recorded ownership, refuses dirty or ambiguous worktrees, never removes another run's files, and reports retained artifacts.

## Required inputs

- `docs/PRODUCT.md`, `docs/ARCHITECTURE.md`, `docs/DB.md`, `docs/FLOW.md`, `docs/SECURITY.md`, and `docs/EXECUTION_ENVIRONMENTS.md`.
- Task `0305-pause-hibernate-resume-and-cleanup.md`.
- Ponytail full, `ponytail-minimalism`, `local-runner`, `security-review`, and `quality-gates` skills.

## Reference coding

- Project XERJ search: `pause hibernate resume checkpoint cleanup ownership environment process worktree`.
- Peer XERJ search: `git worktree remove delete cleanup path canonical ownership metadata`.
- Vibe Kanban revision `735654971bd396aa97b65166955678e4c34f8bf8` is Apache-2.0. Its centralized Git CLI cleanup at `crates/worktree-manager/src/worktree_manager.rs:230-265` is the useful boundary; Cuckoding does not adapt its forced removal or ignored cleanup errors because recorded ownership and retained user work must fail closed.

## Verification

| Check | Result |
| --- | --- |
| `rtk mix test test/cuckoding/execution/lifecycle_test.exs` | Pass: 3 tests, 0 failures. |
| `rtk mix quality` | Initial functional suite passed (8 properties, 67 tests); strict Credo found three small nesting/readability issues, which were simplified before the final run. |
| `rtk mix quality` (final) | Pass: 8 properties, 67 tests, 0 failures; warnings-as-errors compile, strict Credo, Sobelow, and dependency audit passed. |
| `rtk git diff --check` | Pass. |

## Work performed

- Added durable checkpoint projection and runner pause/hibernate/resume callbacks.
- Added lifecycle orchestration that checkpoints before shutdown, releases the in-memory port lease, reloads durable state, blocks resume on ownership/policy drift, and resumes the existing active attempt under a new lease.
- Added safe Git cleanup without force removal. It verifies ownership and cleanliness, refuses running processes, retains the run directory and artifacts, and records a bounded artifact inventory.
- Added a real-server lifecycle test covering pause, hibernate, durable reload, blocked drifted resume, successful same-attempt resume, cleanup, event ordering, artifact retention, and isolation from a sibling run.
- Added failure coverage proving a checkpoint error leaves the process and lease active, plus dirty/changed-marker cleanup refusal.
