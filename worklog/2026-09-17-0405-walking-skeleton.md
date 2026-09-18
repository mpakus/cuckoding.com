# Worklog — 0405 walking skeleton end to end

## Metadata

- Date/time (UTC): 2026-09-17
- Task: 0405
- Status: done
- Human/agent owner: codex
- Branch: `feature/0405-real-demo` (completion), following the partial `feature/0405-walking-skeleton` implementation
- Start revision: `c634ae7`
- End revision: task-closing commit on this branch; see Git history
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
- The completion pass searched the project and both pinned peer indices before each unfamiliar fix. Project guidance at `docs/HOST_AGENT_RUNTIME_SPIKE.md:68,78` requires the agent sandbox to protect the resolved Git directory and assigns commits to the host VCS service; the implementation preserves that boundary instead of weakening provider permissions.
- Agetor commit `eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a` (MIT), `src/shared/types.ts:142-205`, models durable attempts with explicit ordinals. Cuckoding independently keeps failed attempts and allocates `max(attempt) + 1` for a retry under its own event/state-machine rules.
- Vibe Kanban commit `735654971bd396aa97b65166955678e4c34f8bf8` (Apache-2.0), `crates/executors/src/executors/opencode.rs:115-120`, connects null stdin for a noninteractive agent subprocess; `crates/review/src/main.rs:23` also uses an explicit bounded timeout. Cuckoding adapts those behaviors through its supervised runner, persisted process records, and the adapter's validated `wall_ms` limit. No peer code was copied.

## Work performed

- Added idempotent, event-backed stage-attempt transitions with measured active/wall time and durable start/finish timestamps.
- Added the `WalkingSkeleton` coordinator over existing project, workflow, runner, adapter, lifecycle, approval, and event contexts. It creates one default board, runs specification/development/QA, simulates hibernate/resume on the same attempt, writes owner-only evidence and unreviewed project knowledge, and stops for human approval.
- Added candidate commit recording with clean revision, base, branch, ownership-marker, confinement, traversal, and symlink checks.
- Added the `VcsHost` behaviour and a local-bare implementation that requires same-run human approval and performs an idempotent, non-force, terminal-prompt-disabled exact branch push.
- Added a two-step keyboard-accessible LiveView release confirmation and explicit completion feedback.
- Added the fake CI end-to-end regression, real Git/local bare fixtures, idempotency assertions, and adversarial candidate-path coverage.
- Added the architecture, security, testing, development, fake/replacement ledger, demo procedure, and conditional product GO documentation.
- Made failed provider attempts durable and retry ordinals monotonic, then closed the real-provider response schema for Codex structured output.
- Made noninteractive runner stdin reach EOF immediately and made the Codex adapter honor its validated stage `wall_ms` instead of the runner's implicit 60-second default.
- Kept Git metadata protected: the real adapter leaves its confined development patch uncommitted and the host Git service validates changed paths, creates the candidate commit, and records its SHA. Specification and QA now receive read-only grants.
- Enabled the real macOS startup inspector by default and applied the already-tracked `create_power_events` development migration needed by the demo; no new migration was introduced.
- Made release handoff failure-safe: a failed handoff closes the release attempt, an already approved release remains visible and retryable, and startup-recovered waiting handoffs resume without duplicating the approval decision.
- Completed the run-scoped Codex demo and the two-step LiveView release. The first release attempt exposed an untracked fixture `_build/`; after removing that generated directory, the same approved run recovered and pushed through the UI.

## Artifacts

- Commits/patches: partial implementation commit `5d3344d` plus the task-closing commit on `feature/0405-real-demo`
- Migrations: no new migration; applied the existing `20260917211000_create_power_events` migration to the local development database for the demo
- Logs/reports/screenshots: each completed run writes `specification.md`, `qa.md`, `evidence.json`, `release.json`, process logs when applicable, and a project-only knowledge candidate under its owner-only run directory
- Configuration or policy hashes: walking-skeleton policy source SHA-256 `7d7ca95a69eb510da73029387929ac7c24225287cb97921617636074438d2f69`
- Real demo: run `01a0b1e6-ae77-73d3-85cd-a368d5eed432`; approval `01a0b22c-d6a8-7c7d-927f-81a8a7cb9e20`; branch `feature/walking-01a0b1e6`; candidate and remote SHA `5c040f3bae8652f4cf57b9315b49debd164d4ca3`
- Real evidence hashes: `evidence.json` `056a1fc184f45c3de94471786ddeee8465309e682c902ffb85c9eb25380022a0`; `release.json` `a9dd4019064082e7207f2cef72eecdcc32380b78e63e01071a52e7d764d9dbab`; both verified mode `0600`

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| Project and pinned Vibe Kanban XERJ searches | pass | Required sources retrieved before implementation; pinned revision and Apache-2.0 license verified locally. |
| `rtk mix test test/cuckoding/walking_skeleton_test.exs test/cuckoding/state_machine_test.exs test/cuckoding/execution/git_service_test.exs test/cuckoding_web/status_live_test.exs` | pass | 2 properties, 14 tests, 0 failures. |
| `rtk mix test test/cuckoding/walking_skeleton_test.exs test/cuckoding/execution/git_service_test.exs` | pass | 9 tests, 0 failures after adding path-adversarial and release-replay checks. |
| `rtk mix test test/cuckoding/adapters/codex_test.exs test/cuckoding/execution/local_process_runner_test.exs test/cuckoding/execution/command_policy_test.exs test/cuckoding/walking_skeleton_test.exs` | pass | 21 tests, 0 failures for timeout propagation, stdin EOF, changed-path inspection, provider retries, schema/grants, and host candidate commit. |
| `rtk mix test test/cuckoding/walking_skeleton_test.exs` after release-retry fix | pass | 6 tests, 0 failures; includes durable failed handoff and approved retry without a second approval decision. |
| `rtk mix format --check-formatted mix.exs lib/greeting.ex test/test_helper.exs test/greeting_test.exs` in the real candidate | pass | The bare formatter invocation first reported the fixture had no `.formatter.exs`; the explicit source-file check passed. |
| `rtk mix test` in the real candidate | pass | 2 tests, 0 failures, run independently by the host because Mix was absent from the provider-safe PATH. |
| Run-scoped Codex `0.146.0` | pass | Authenticated only inside the run home; no global provider credentials were copied or committed. |
| Real-provider stage run | pass | Specification 25,462 ms; development 46,781 ms; QA 42,312 ms. Attempts 1–5 remain durably failed with their surfaced integration causes; attempt 6 and both downstream stages succeeded. |
| LiveView approval and local release | pass | Browser showed the confirmation and final success notice; SQLite records run/task `done`, approval `approved`, and release attempt `succeeded`; candidate and remote SHA both equal `5c040f3b...`. |
| Owner-only artifact and hash checks | pass | `evidence.json` and `release.json` are `0600`; SHA-256 values are recorded above. |
| `rtk mix quality` | pass | 8 properties, 95 tests, 0 failures in 11.4 seconds; warnings-as-errors compilation, strict Credo with no findings, Sobelow, and dependency retirement/security audit passed. The first run found one stale inspector assumption and one Credo nesting finding; focused fixes passed 1 property and 12 tests before this clean rerun. |
| `rtk git diff --check` | pass | No whitespace errors after the final source and documentation edits. |
| XERJ focused retrieval | pass | Project, Agetor, and Vibe Kanban indices returned the cited attempt, stdin, timeout, and host-VCS sources. The completion pass used existing indices rather than claiming a refreshed generation. |

## Telemetry and operational evidence

- Final full repository gate: 11.4 seconds reported by ExUnit for 8 properties and 95 tests on this host.
- Focused workflow/state/Git/LiveView gate: 3.8 seconds reported by ExUnit for 2 properties and 14 tests.
- Real Codex evidence records measured monotonic active/wall time of 25,462 ms for specification, 46,781 ms for development, and 42,312 ms for QA. These are measured run evidence, not estimates.

## Decisions and deviations

- Reuse the established VCS-host boundary from ADR-013/ADR-015; no new architecture boundary or ADR is required.
- Keep artifacts and knowledge candidates as plain files plus durable events for this skeleton. Phase 7 owns the full knowledge persistence model.
- Do not copy global Claude/Codex credentials into run-scoped homes. The stakeholder completed the isolated device login directly for this run.
- The Codex sandbox correctly prevented agent-side Git metadata access. Cuckoding owns the commit and release through host services; it does not relax the sandbox to satisfy an agent prompt.
- The release remains recoverable after approval. Approval is a durable human fact, while each handoff attempt has its own durable state and can be retried after startup reconciliation.
- Operational log inspection attempted `rtk proxy tail` once because exact streaming output was desired; RTK's tail adapter still emitted its filter prompt, so subsequent exact inspection used RTK-wrapped `sed`, `rg`, SQLite, and session output.

## Risks and blockers

- The provider-safe PATH did not expose the fixture's Mix executable, so provider-reported test execution was unavailable. The host independently ran formatting and two tests successfully. Phase 5 runner/toolchain resolution must make declared project tools available without widening unrelated host access.
- The demo's first release attempt was blocked by the generated, unignored `_build/` directory. The recovered retry proves the new release path; future demo fixtures should ignore build output before verification.

## Handoff

Task 0405 is complete and ready to fast-forward into local `main`. Continue with task 0501, carrying forward the toolchain-resolution gap and preserving the demonstrated host-owned Git and retry boundaries.

## Checklist

- [x] Task acceptance criteria reviewed.
- [x] Relevant documentation updated.
- [x] Tests and checks recorded honestly.
- [x] Secrets and sensitive content excluded/redacted.
- [x] Residual risks and skipped work are explicit.
- [x] Task status and next owner are updated.
