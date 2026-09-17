# Worklog — 0303 Command policy and protected paths

## Metadata

- Date/time (UTC): 2026-09-17T22:05:31Z
- Task: 0303
- Status: done
- Human/agent owner: Codex
- Branch: `feature/0303-command-policy`
- Start revision: `2a647b0`
- End revision: task commit
- Environment: Apple Silicon macOS 27.0, Erlang/OTP 28.4, Elixir/Mix 1.19.5

## Intended outcome

Execute only trusted commands declared in `project.yml`, classify every policy field honestly as enforced or advisory, and block QA when a commit or diff changes a protected path until a human approval exists.

## Acceptance criteria restated

- Cuckoding rejects undeclared commands and resolves declared commands only from the run's trusted configuration snapshot.
- Policy fields expose an explicit enforced/advisory classification; UI-facing labels cannot present advisory host-runner controls as enforced.
- Commit and working-tree scans detect protected paths, including `.cuckoding/`, and create or require an approval before QA can pass.
- A malicious repository fixture covers undeclared commands, traversal-like paths, protected configuration changes, and approval release.

## Context inspected

- Required product, architecture, database, workflow, security, execution-environment, testing, configuration, and dashboard documentation.
- Task 0303 and merged local runner at `2a647b0`.
- Mandatory Ponytail full, local-runner, security-review, and quality-gates skills.

## Work performed

- Claimed the task and restated its acceptance criteria before implementation.
- Added a size-bounded `project.yml` loader using pinned `yaml_elixir` 2.12.2, source hashing, version/security-field validation, shell-free tokenization, and declared-name lookup against the run's immutable trusted snapshot.
- Added direct argv execution through `RunnerBridge`; undeclared commands, shell executables, NUL arguments, absolute argument paths, and parent traversal fail closed.
- Added NUL-delimited protected-path scans across the frozen-base commit range plus staged, unstaged, and untracked changes. Rename/copy detection checks both old and new paths, and `.cuckoding/` is always protected.
- Added digest-scoped QA approvals. Pending and rejected decisions block; an approval passes only the exact run/stage/path set. Decisions use a pending-only atomic update and append a durable audit event.
- Added an accessible enforced/advisory badge and malicious repository fixtures covering command policy, protected config/workflow changes, and rename behavior.

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| `rtk xerj search 'declared commands command allowlist protected paths git diff changed files approval policy advisory enforced' -k 12 --prefix cuckoding-project-v7` | pass | Retrieved project policy, threat-model, and host-runtime boundaries before implementation. |
| `rtk xerj search 'command allowlist protected files git diff approval configuration trusted' -k 12 --prefix ref-vibe-kanban-v1` | pass | Retrieved the pinned peer's structured Git-diff and approval paths before implementation. |
| `rtk mix test test/cuckoding/execution/command_policy_test.exs test/cuckoding_web/policy_components_test.exs` | pass | 5 tests, 0 failures; symlinked config, malicious declarations, exact approvals, rejection, rename detection, and advisory UI labels passed. |
| `rtk mix quality` | pass | 8 properties and 59 tests, 0 failures; warnings-as-errors compile, strict Credo, Sobelow, and dependency audit passed. |
| `rtk git diff --check` | pass | No whitespace errors in the completed task diff. |
| `rtk xerj autoindex . --no-graph --prefix cuckoding-project-v7 ...` | pass | Final task generation indexed after all source and documentation changes; the temporary flood-stage override was restored. |

## Decisions and deviations

- Ponytail full 4.10.0 (MIT) kept policy in two focused modules and one shared UI component, reused immutable config/approval/event rows and `RunnerBridge`, and added only the YAML parser the product format requires. No shell-command framework or generalized policy DSL was introduced.
- `yaml_elixir` 2.12.2 (MIT) is pinned with its pure-Erlang `yamerl` 0.10.0 dependency. A maintained parser is used instead of an incomplete repository-owned YAML grammar.
- XERJ retrieved Vibe Kanban pinned revision `735654971bd396aa97b65166955678e4c34f8bf8` (Apache-2.0). Its Git layer models name-status entries and parses both rename/copy paths at `crates/git/src/cli.rs:47-66,215-227,466-509`; its Codex client returns approval-service failures instead of continuing at `crates/executors/src/executors/codex/client.rs:456-499`. Cuckoding adds NUL-delimited names, immutable trusted snapshots, an unconditional `.cuckoding/` root, exact change-set digests, and same-transaction audit events.

## Risks and blockers

- Command validation detects declared lexical path escapes but does not confine arbitrary behavior inside a trusted child executable. The runtime permission layer and trusted-host warning remain required; this feature is not a sandbox.
- Executable names are resolved from the application's configured host tool path at execution time and passed onward as absolute paths. A later tool-discovery task should surface path/version provenance in settings and run evidence.

## Handoff

Task complete. Proceed to 0304 for leased ports and preview URLs.

## Checklist

- [x] Task acceptance criteria reviewed.
- [x] Relevant documentation updated.
- [x] Tests and checks recorded honestly.
- [x] Secrets and sensitive content excluded/redacted.
- [x] Residual risks and skipped work are explicit.
- [x] Task status and next owner are updated.
