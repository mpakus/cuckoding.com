# Worklog — 0405 walking skeleton end to end

## Metadata

- Date/time (UTC): 2026-09-17
- Task: 0405
- Status: in progress
- Human/agent owner: codex
- Branch: `feature/0405-walking-skeleton`
- Start revision: `c634ae7`
- End revision: partial implementation merged by stakeholder direction; see Git history
- Environment and relevant tool versions: macOS 27.0 arm64; OTP 28; Elixir/Mix 1.19.5; Git 2.51.1; XERJ 1.0.0-rc.74; RTK 0.49.0

## Intended outcome

Deliver one durable project → board → task → specification → development → QA → human approval → host-side local-bare-remote handoff loop. The CI lane uses the deterministic fake adapter; the demo lane must use a supported real adapter. Evidence and project-scoped knowledge candidates remain owner-only plain files. A simulated sleep gap must resume the same stage attempt without duplicate work.

## Context inspected

- `docs/PRODUCT.md`, `docs/ARCHITECTURE.md`, `docs/DB.md`, `docs/FLOW.md`, `docs/SECURITY.md`, `docs/EXECUTION_ENVIRONMENTS.md`, `docs/DECISIONS.md`, and `docs/REFERENCE_CODING.md`.
- Task 0405 and the completed Phase 2–04 worklogs, context modules, transition/event store, worktree/lifecycle services, adapter contract and fake adapter, Status LiveView, schemas, and focused tests.
- Mandatory Ponytail full mode plus the workflow, architecture, Elixir/LiveView, adapter, security-review, and quality-gates skills.
- The branch was clean at `c634ae7` before the task claim.

## Reference coding

- Project XERJ search: `walking skeleton approval release handoff local bare remote evidence bundle knowledge candidate sleep resume duplicate`.
- Pinned Vibe Kanban search: `approve merge push branch local remote execution process task attempt`.
- Vibe Kanban commit `735654971bd396aa97b65166955678e4c34f8bf8` (Apache-2.0) constructs an explicit non-force `refs/heads/<branch>:refs/heads/<branch>` refspec and disables terminal prompting at `crates/git/src/cli.rs:368-397`. Cuckoding will adapt only that bounded push shape, adding an approved durable decision, local-bare-remote validation, recorded ownership, and audit events.

## Work performed

- Added idempotent, event-backed stage-attempt transitions with measured active/wall time and durable start/finish timestamps.
- Added the `WalkingSkeleton` coordinator over existing project, workflow, runner, adapter, lifecycle, approval, and event contexts. It creates one default board, runs specification/development/QA, simulates hibernate/resume on the same attempt, writes owner-only evidence and unreviewed project knowledge, and stops for human approval.
- Added candidate commit recording with clean revision, base, branch, ownership-marker, confinement, traversal, and symlink checks.
- Added the `VcsHost` behaviour and a local-bare implementation that requires same-run human approval and performs an idempotent, non-force, terminal-prompt-disabled exact branch push.
- Added a two-step keyboard-accessible LiveView release confirmation and explicit completion feedback.
- Added the fake CI end-to-end regression, real Git/local bare fixtures, idempotency assertions, and adversarial candidate-path coverage.
- Added the architecture, security, testing, development, fake/replacement ledger, demo procedure, and conditional product GO documentation.

## Artifacts

- Commits/patches: task 0405 partial implementation on `feature/0405-walking-skeleton`; merged to local `main` by explicit stakeholder direction while the real demo gate remains open
- Migrations: none
- Logs/reports/screenshots: each completed run writes `specification.md`, `qa.md`, `evidence.json`, `release.json`, process logs when applicable, and a project-only knowledge candidate under its owner-only run directory
- Configuration or policy hashes: walking-skeleton policy source SHA-256 `7d7ca95a69eb510da73029387929ac7c24225287cb97921617636074438d2f69`

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| Project and pinned Vibe Kanban XERJ searches | pass | Required sources retrieved before implementation; pinned revision and Apache-2.0 license verified locally. |
| `rtk mix test test/cuckoding/walking_skeleton_test.exs test/cuckoding/state_machine_test.exs test/cuckoding/execution/git_service_test.exs test/cuckoding_web/status_live_test.exs` | pass | 2 properties, 14 tests, 0 failures. |
| `rtk mix test test/cuckoding/walking_skeleton_test.exs test/cuckoding/execution/git_service_test.exs` | pass | 9 tests, 0 failures after adding path-adversarial and release-replay checks. |
| `rtk mix quality` | pass | 8 properties, 90 tests, 0 failures; warnings-as-errors compilation, strict Credo with no findings, Sobelow, and dependency retirement/security audit passed. |
| `rtk git diff --check` | pass | No whitespace errors before commit. |
| Fresh run-scoped Codex probe | blocked | Installed Codex `0.146.0` is available but the isolated home reports `authentication_required`; global credentials were not copied. |
| Real-provider demo | blocked | The durable demo run and dedicated local repository/bare remote are prepared outside the repository; the run-scoped device-auth process is waiting for the stakeholder confirmation. |
| XERJ refresh | not retried | Generation 22 remains sealed behind the node's disk flood-stage protection; generation 21 is the last committed project index. |

## Telemetry and operational evidence

- Full repository gate: 8.8 seconds reported by ExUnit for 8 properties and 90 tests on this host.
- Focused workflow/state/Git/LiveView gate: 3.8 seconds reported by ExUnit for 2 properties and 14 tests.
- Each walking-skeleton `evidence.json` stores the measured monotonic active and wall milliseconds for specification, development, and QA. These values are run evidence rather than estimates.

## Decisions and deviations

- Reuse the established VCS-host boundary from ADR-013/ADR-015; no new architecture boundary or ADR is required.
- Keep artifacts and knowledge candidates as plain files plus durable events for this skeleton. Phase 7 owns the full knowledge persistence model.
- Do not copy global Claude/Codex credentials into run-scoped homes. The real demo remains blocked until a run-scoped provider login exists.
- By explicit stakeholder instruction, merge the verified partial implementation to local `main` while retaining task status `in_progress` and leaving the real-provider checkbox open.

## Risks and blockers

- A successful real-adapter demo cannot be claimed from fixture conformance. Codex currently fails closed until the prepared run-scoped device login completes.
- The phase checkpoint is not complete and Phase 4 must not be reported complete until the real demo produces its branch and evidence bundle.

## Handoff

After the stakeholder completes the pending run-scoped Codex device login, execute run `01a0b1e6-ae77-73d3-85cd-a368d5eed432` with `simulate_sleep_gap: false`, inspect its provider logs and candidate commit, approve through LiveView, verify the bare-remote SHA, attach sanitized evidence, and only then mark 0405 done.

## Checklist

- [x] Task acceptance criteria reviewed.
- [x] Relevant documentation updated.
- [x] Tests and checks recorded honestly.
- [x] Secrets and sensitive content excluded/redacted.
- [x] Residual risks and skipped work are explicit.
- [x] Task status and next owner are updated.
