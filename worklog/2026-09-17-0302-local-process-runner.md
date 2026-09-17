# Worklog — 0302 Local process runner

## Metadata

- Date/time (UTC): 2026-09-17T21:39:51Z
- Task: 0302
- Status: done
- Human/agent owner: Codex
- Branch: `feature/0302-local-process-runner`
- Start revision: `33e5fe7`
- End revision: task commit
- Environment: Apple Silicon macOS 27.0, Erlang/OTP 28.4, Elixir/Mix 1.19.5

## Intended outcome

Implement the host `RunnerBridge` with one supervised process group per command, a fresh allowlisted environment, durable PID/start identity, bounded and redacted output, timeout handling, an observable termination ladder, and resource inspection.

## Acceptance criteria restated

- Every child starts in its own process group and termination leaves no owned descendants.
- Only allowlisted environment values reach the child; Cuckoding-managed secrets and inherited ambient variables do not.
- PID plus process start identity is verified before inspection or signalling.
- Timeouts and explicit stop use the bounded `SIGINT` → `SIGTERM` → `SIGKILL` ladder and record every attempted step.
- Output exceeding the configured bound is truncated explicitly and the complete redacted stream is retained as an artifact.
- Focused checks cover cleanup, timeout, PID reuse, output bounds, and environment scrubbing.

## Context inspected

- Required architecture, execution, security, database, workflow, and testing documents.
- Task 0302 and merged worktree lifecycle at `33e5fe7`.
- Mandatory Ponytail full, local-runner, security-review, and quality-gates skills.

## Work performed

- Added the `RunnerBridge` behaviour, a deterministic fake, and `LocalProcessRunner` operations for prepare, async start, sync exec, inspection, durable event retrieval, stop, and environment-wide destroy.
- Added one temporary supervised worker per external process. Each launch records PID, PGID, and the macOS `ps` start identity before the target runs, then persists a start event.
- Built child environments from scratch with a fixed system path, per-run home, locale/timezone defaults, explicit Cuckoding variables, and policy additions. Ambient values, undeclared names, and credential-shaped names are rejected or removed.
- Added redaction-before-write, mode-`0600` full output artifacts, bounded previews, SHA-256 evidence, and durable truncation events.
- Added read-only process-group sampling for identity, descendant groups, process count, and RSS; fixed the sampler to take one ownership snapshot rather than re-running `ps` per host process.
- Added PID-reuse refusal and the `SIGINT` → `SIGTERM` → `SIGKILL` ladder with descendant groups before the root group, a durable event before every signal, bounded waits, and a final no-process verification.

## Artifacts

- Commits/patches: task commit
- Migrations: none
- Logs/reports/screenshots: this worklog
- Configuration or policy hashes: unchanged

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| `rtk xerj search 'process group setsid kill descendants SIGINT SIGTERM SIGKILL timeout stdout stderr bounded environment allowlist start time pid' -k 10 --prefix ref-vibe-kanban-v1` | pass | Retrieved the pinned process-group termination helper before implementation. |
| `rtk mix test test/cuckoding/execution/local_process_runner_test.exs` | pass | 6 real-process tests, 0 failures; environment scrubbing, redaction, output bounds, descendant cleanup, timeout, PID reuse, sampling, and destroy passed. |
| `rtk mix quality` | pass | 8 properties and 54 tests, 0 failures; warnings-as-errors compile, strict Credo, Sobelow, and dependency audit passed. |
| `rtk git diff --check` | pass | No whitespace errors in the completed task diff. |
| `rtk xerj autoindex . --no-graph --prefix cuckoding-project-v7 ...` | pass | Final task generation indexed after all source and documentation changes; the temporary flood-stage override was restored. |

## Decisions and deviations

- Ponytail full 4.10.0 (MIT) used OTP ports, standard macOS tools, the existing process/event schemas, and one small argv-preserving launch shim; no command framework, NIF, or third-party process dependency was added.
- XERJ retrieved Vibe Kanban pinned revision `735654971bd396aa97b65166955678e4c34f8bf8` (Apache-2.0). Its helper signals the captured group with `SIGINT`, `SIGTERM`, and `SIGKILL`, stopping when `ESRCH` proves the group is gone, at `crates/utils/src/process.rs:5-30`. Cuckoding adapts the sequence with durable pre-signal events, PID/start-identity verification, descendant-group ordering, and a final process-table check.
- The repository spike at `spikes/0002-host-runtime/host_runtime_spike.rb:143-152,334-352` supplied the project-specific environment-clearing, PID/PGID/start-identity, and descendant-snapshot boundary.

## Risks and blockers

- This is trusted-host process supervision, not a sandbox. A hostile same-user process can race `ps` inspection, and descendants can deliberately daemonize after the ownership snapshot; task 1001 owns the adversarial escape drill.
- `/usr/bin/ruby` is used only as a 50 ms argv-preserving pre-exec delay so the durable identity is recorded even for short commands. It is present on the supported macOS target but must be included in clean-machine packaging checks; replace it with a bundled native launcher if Apple removes it.
- Stdout and stderr are intentionally combined in order for the MVP artifact. Provider adapters may add typed stream parsing without weakening the common redaction and byte-bound boundary.

## Handoff

Task complete. Proceed to 0303 for declared-command policy and protected-path enforcement.

## Checklist

- [x] Task acceptance criteria reviewed.
- [x] Relevant documentation updated.
- [x] Tests and checks recorded honestly.
- [x] Secrets and sensitive content excluded/redacted.
- [x] Residual risks and skipped work are explicit.
- [x] Task status and next owner are updated.
