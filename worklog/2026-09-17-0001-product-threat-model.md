# Worklog — 0001 Product boundaries, competition, and threat model

## Metadata

- Date/time (UTC): 2026-09-17
- Task: 0001
- Status: done
- Human/agent owner: Codex
- Branch: `feature/0001-product-threat-model`
- Start revision: `d53de8d`
- End revision: task-closing commit (see Git history)
- Environment: macOS Apple Silicon planning and security review

## Intended outcome

Confirm the MVP boundary, positioning, launch adapters, product hypotheses, trusted-host threat model, risk ownership, approval gates, retention defaults, and residual-risk disclosures.

## Context inspected

- `docs/PRODUCT.md`, `docs/ARCHITECTURE.md`, `docs/DB.md`, `docs/FLOW.md`, `docs/SECURITY.md`, `docs/EXECUTION_ENVIRONMENTS.md`, `docs/PLAN.md`, `docs/DECISIONS.md`, and `docs/TESTING.md`.
- Task 0001 acceptance criteria and the mandatory Ponytail, architecture, security-review, quality-gates, and OpenAI documentation guidance.
- Clean `main` at `d53de8d` before task-branch creation.

## Work performed

- Queried the current project index and the pinned Agetor, Vibe Kanban, and Hydra reference indexes before drafting.
- Checked current official documentation for Claude Code agents, worktrees, permissions, and sessions; OpenAI agent configuration; Cursor background agents and pricing; and the Apache/OSI license definitions.
- Fixed the launch contract at macOS Apple Silicon, single user, trusted host runner, Claude Code plus Codex, loopback LiveView UI, durable SQLite state, and host-side VCS handoff.
- Defined data classes, retention defaults, outbound-telemetry opt-in, the product wedge, public-name gate, license hypothesis, pricing hypothesis, and interview script.
- Enumerated assets, attackers, trust boundaries, mandatory approvals, fourteen owned risks, validation tasks, residual risks, and the malicious-repository tabletop.
- Applied the Ponytail full-mode review: kept the result to two new specifications plus links/ADRs in existing authoritative documents; added no implementation, dependency, or speculative abstraction.

## Artifacts

- `docs/MVP_BOUNDARY_AND_POSITIONING.md`
- `docs/TRUSTED_HOST_THREAT_MODEL.md`
- ADR-017 through ADR-020 in `docs/DECISIONS.md`
- Root Apache-2.0 `LICENSE`
- Synchronized `docs/PRODUCT.md`, `docs/SECURITY.md`, and `README.md`

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| `rtk xerj search --prefix cuckoding-project-v3 -k 8 "trusted host threat boundaries approvals retention telemetry launch adapters"` | pass | Retrieved current project constraints before writing. |
| `rtk xerj search --prefix ref-vibe-kanban-v1 -k 8 "worktree task agent process permissions orchestration"` | pass | Retrieved worktree, approval, and cleanup patterns. |
| `rtk xerj search --prefix ref-agetor-v1 -k 8 "agent token environment permissions worktree security"` | pass | Retrieved local-first, full-host-privilege, approval, and persistence evidence. |
| `rtk xerj search --prefix ref-hydra-v1 -k 8 "workspace agents lifecycle orchestration resume"` | pass | Retrieved process identity, recovery, and risk-gate patterns. |
| Pinned source inspection at Agetor `eb74ab5f`, Vibe Kanban `73565497`, and Hydra `d8ad5611` | pass | Exact files and line ranges are recorded in the positioning document. |
| Official-source web review | pass | Links and claims are recorded in `docs/MVP_BOUNDARY_AND_POSITIONING.md`; checked 2026-09-17. |
| Sole-stakeholder review | pass | The user approved the MVP boundary and will lead the controlled-beta interviews on 2026-09-17. |
| Apache-2.0 license review | pass | Root `LICENSE` uses the standard text linked from the accepted ADR. |
| Threat-boundary coverage review | pass | Each boundary maps to at least one risk and primary control; every High-impact risk has an owner and validation task. |
| Validation-task reference check | pass | All 21 task IDs named by the risk register resolve to task files. |
| Malicious-repository tabletop | pass | Records both enforced controls and the unresolved unrestricted-host-shell risk. |
| `rtk git diff --check` | pass | No whitespace errors in tracked changes. |
| New-file whitespace check | pass | The two specifications and worklog contain no accidental trailing whitespace. |
| `rtk proxy markdownlint ...` | unavailable | No `markdownlint` executable is installed; no dependency was added for a documentation-only task. |

## Telemetry and operational evidence

No runtime telemetry applies to this discovery task.

## Decisions and deviations

- Claude Code and Codex are the two launch-supported adapters; Cursor Agent and OpenCode remain contract-compatible stubs until conformance passes.
- Outbound analytics/crash telemetry is off by default. Required local operational evidence remains enabled.
- `Cuckoding` is an internal codename. The public name is deferred to 2026-10-01.
- The sole stakeholder approved the MVP boundary, internal-name deferral, Apache-2.0 open-core license, and Community/Pro/Teams interview hypothesis on 2026-09-17.
- Community/Pro/Teams prices remain interview hypotheses, not shipped commitments.
- The sole stakeholder owns 3–5 developer interviews during controlled beta task 1003; participant and calendar details stay outside Git.
- No task implementation code exists yet, so compile/test/runtime gates do not apply to this documentation decision task.

## Risks and blockers

- The host runner cannot confine an arbitrary runtime launched with unrestricted shell permissions; this is a disclosed residual risk and a Phase 3/10 validation focus.

## Handoff

Task 0001 is complete. Begin task 0002 with Claude Code as the first observed host runtime; task 1003 owns the approved controlled-beta interview follow-up.

## Checklist

- [x] Task acceptance criteria reviewed.
- [x] Relevant documentation updated.
- [x] Tests and checks recorded honestly.
- [x] Secrets and sensitive content excluded/redacted.
- [x] Residual risks and skipped work are explicit.
- [x] Task status and next owner are updated.
