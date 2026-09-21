# Dogfood and Controlled Beta Report

**Task:** 1003

**Status:** prepared; external beta not started

**Last updated:** 2026-09-21

**Owner:** sole stakeholder

This is the anonymized evidence ledger for `docs/BETA_RUNBOOK.md`. It does not
contain participant names, contact details, calendar information, repository
names, private URLs, source code, prompts, secrets, or unredacted diagnostics.
Blank rows mean `not observed`; they are not passing evidence.
The current operator guide and no-go decision are in
[`RELEASE_READINESS.md`](RELEASE_READINESS.md).

## Pre-beta gate

| Gate | Status | Evidence or action |
| --- | --- | --- |
| Deterministic and physical recovery matrix | pass | Task 1002, 27/27 observations; this is prerequisite evidence and does not count as a beta run |
| MVP definition-of-done audit | partial; no-go | The ten-item matrix in `docs/RELEASE_READINESS.md` separates source/fixture evidence from current signed-build and participant observations. The integrated delivery-task recovery item is reopened in `docs/PLAN.md`; the 27/27 drill result remains valid prerequisite evidence. |
| Current-source developer bundle | pass, unsigned only | 2026-09-21: `bin/dev.build` produced a macOS `.app` and its sterile verifier passed startup, token/session, crash, safe-mode, and update/rollback checks after the pre-READY fixture was made deterministic. This does not satisfy signed enrollment or clean-Mac acceptance |
| Release CI source gate | first run failed; rerun pending | [Manual run 35662057281](https://github.com/mpakus/cuckoding.com/actions/runs/35662057281) on `131e171` installed pinned tools, then failed two Claude adapter tests at `mix quality` before certificate import. Their fixture now selects an explicit executable; local quality passes, but CI must be rerun. No signed candidate is accepted. |
| Signed and notarized build identified | pending fresh build | Local Developer ID identity, `Cuckoding` notary profile, private updater key file, and GitHub Releases public URLs are present. The retained signed ZIP's provenance names source `4a2cf53`, not current main. Local release variables are not set in this shell; CI lacks the Apple certificate/password and App Store Connect notary key/ID/issuer secrets. The release script now stages the next candidate and retains the older artifact, but no new Apple submission or signed enrollment build has been run. |
| Claude Code adapter conformance | pass for current fixture contract | 2026-09-18 focused adapter suite; real beta use still requires separately verified run-scoped authentication |
| Codex adapter conformance | pass for current fixture contract | Saved sign-in uses its private app-owned file profile; an isolated run HOME must still launch a real task without copied credentials |
| Saved Codex and Cursor sign-in preflight | pass for CLI status only | 2026-09-21 19:52 UTC: each installed CLI reported authenticated with only its app-owned profile and a scrubbed environment. No token content was read and no provider task was launched; two-project execution, refresh and concurrency remain unobserved |
| Previously exposed provider key rotated | pending stakeholder confirmation | An earlier host process exposed a provider key in its arguments; no new paid provider run was launched during this preflight |
| Outbound product telemetry off | source preflight only; enrolled build pending | Local resource collection writes to SQLite; diagnostics require an explicit UI/menu action, and update network access follows the explicit Check for Updates menu action. Source inspection is not a network observation on the signed enrollment build. Provider and approved release-handoff traffic are separate disclosures. |
| Resource retention default | code-level safety verified; enrolled build pending | Automatic pruning waits for both minute and finished-stage aggregates. Synthetic eight-day and 121-minute backlog regressions pass; each maintenance tick processes at most 120 missing session-minutes and resumes from durable rows. Effective retention and participant-facing consent/defaults on the signed enrollment build remain unobserved. |
| Agent/output artifact retention | policy and enrolled build pending | The UI preview is bounded, but full redacted artifacts and persisted provider diagnostic fragments have no automatic age purge. Define participant-facing retention and verified cleanup before enrollment; do not promise a 30-day deletion. |
| Host-runner and provider-policy disclosure | pending | sole stakeholder confirms before each participant session |
| Dedicated sanitized repositories and data roots | pending | record only anonymized codes and starting SHAs |

## Repository and run ledger

Use one row per observation. Evidence identifiers must resolve locally without
revealing a private repository name or URL.

| Run | Participant | Repository shape | Build / start SHA | Runtime / model | Workflow observation | UTC start / end | Active / wall time | Outcome | Evidence | Findings |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| D01 | — | Elixir/Phoenix (`R01`) | — | — | happy path + release handoff | — | — | not observed | — | — |
| D02 | — | Node/frontend (`R02`) | — | — | QA return to development | — | — | not observed | — | — |
| D03 | — | mixed/polyglot (`R03`) | — | — | concurrent boards | — | — | not observed | — | — |
| D04 | — | one of `R01`–`R03` | — | — | real sleep/wake, at least 24h wall time | — | — | not observed | — | — |
| D05 | — | one of `R01`–`R03` | — | — | app quit/relaunch | — | — | not observed | — | — |

## Isolation checks

| Observation | Status | Evidence | Finding |
| --- | --- | --- | --- |
| Concurrent worktrees remain distinct | not observed | — | — |
| Port ranges and process groups do not cross | not observed | — | — |
| Events, artifacts, and approvals remain board-scoped | not observed | — | — |
| Project knowledge cannot be retrieved by another project | not observed | — | — |
| Agent environment excludes host/provider credentials | not observed | — | — |
| Shared sign-in executes tasks in two projects without another login | not observed | Isolated CLI status is preflight only | — |
| Release occurs only after recorded human approval | not observed | — | — |

## Knowledge review

Scores use the 0–2 rubric in `docs/BETA_RUNBOOK.md`. The total alone cannot
override a required dimension or a critical Safety/Scope failure.

| Review | Participant | Project | Item ID / version | Correct | Scope | Action | Fresh | Provenance | Safety | Total | Decision / later-use evidence |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| K01 | — | — | — | — | — | — | — | — | — | — | not reviewed |
| K02 | — | — | — | — | — | — | — | — | — | — | not reviewed |
| K03 | — | — | — | — | — | — | — | — | — | — | not reviewed |

## Interview ledger

Record the participant role and multi-agent experience broadly enough to
verify cohort coverage without making the participant identifiable.

| Participant | Broad role | Runs 2+ agents | Session date | Beta run | Notes recorded | Consent retained outside Git |
| --- | --- | --- | --- | --- | --- | --- |
| B01 | — | — | — | — | pending | — |
| B02 | — | — | — | — | pending | — |
| B03 | — | — | — | — | pending | — |
| B04 | optional | — | — | — | pending | — |
| B05 | optional | — | — | — | pending | — |

### Anonymized interview notes

For each completed interview, append this compact block. Keep observation,
participant statement, and stakeholder interpretation distinct.

```md
### B0X — YYYY-MM-DD

- Context: broad role; broad repository shape; current runtime mix.
- Observed: actions or friction seen during the beta run.
- Participant said: concise anonymized statements.
- Security/trust: blockers, required evidence, provider-policy concerns.
- Positioning: participant's paraphrase and audience boundary.
- Name: Runstead / Branchyard / Agent Harbor response.
- License: Apache-2.0 core expectation and paid-boundary response.
- Pricing: current spend, value trigger, and reaction to hypotheses.
- Findings: `F-...`.
- Stakeholder interpretation: inference, explicitly labeled.
```

## Finding ledger

Do not delete a resolved finding. Retain its original severity, closure or
acceptance evidence, retest, and decision owner.

| ID | Severity | Observation | Evidence | Status | Owner | Closure/retest or acceptance rationale and expiry |
| --- | --- | --- | --- | --- | --- | --- |
| F-1003-001 | High | A new user could not register a repository, create a board/task, or start a workflow from the shipped UI | Original evidence: `lib/cuckoding_web/router.ex:38-49`; `lib/cuckoding_web/live/status_live.ex`; `lib/cuckoding_web/live/board_live.ex`; only the internal `WalkingSkeleton.create/1` assembled the flow | closed locally; enrollment build pending | codex | dashboard now validates and queues the project-to-worktree flow; run control verifies scoped auth before start; 15 focused tests and full gate with 206 tests pass |
| F-1003-002 | High | The replacement onboarding form still combined project registration, agent configuration, first board/task, run, branch, and worktree creation; it did not present existing projects as the primary product object | Sole stakeholder review and screenshot, 2026-09-18; former `lib/cuckoding_web/live/status_live.ex` `guided-run-form` | closed locally; current-flow provider and enrollment evidence pending | codex | Three-step registration, separate saved-agent/role settings, board creation, manual/planned Draft tasks, and explicit run preparation/launch are implemented. The 2026-09-19 documentation audit records remaining shared-authentication and beta gates; snapshots are not retroactively upgraded. |

## Decision synthesis

Require evidence from more than one participant for a general product claim;
retain important disagreement instead of averaging it away.

| Hypothesis | Evidence summary | Decision | Owner / date |
| --- | --- | --- | --- |
| Positioning | pending 3–5 interviews | pending | sole stakeholder / — |
| Public name | pending 3–5 interviews and screening | pending | sole stakeholder / — |
| Apache-2.0 local core | pending interview review and owner/legal approval | pending | sole stakeholder / — |
| Community / Pro boundary | pending 3–5 interviews | pending | sole stakeholder / — |
| $20/month or $200/year Pro | pending 3–5 interviews | pending | sole stakeholder / — |
| Future $40/user/month Teams | pending small-team evidence | pending | sole stakeholder / — |

## Exit review

- [ ] Three authorized repositories and required workflow variations are
  evidenced.
- [ ] Claude Code, Codex, and Cursor Agent each complete a default workflow.
- [ ] Two boards run concurrently without crossover.
- [ ] One beta run spans real sleep/wake and at least 24 wall-clock hours.
- [ ] Quit/relaunch recovery completes without duplicated work.
- [ ] Knowledge candidates are scored and one accepted item has later-use
  evidence.
- [ ] Three to five anonymized developer interviews are summarized.
- [ ] Positioning, name, license, and pricing hypotheses have stakeholder
  decisions or explicitly dated deferrals.
- [ ] Every finding has a disposition.
- [ ] Every critical finding is closed and retested or explicitly accepted by
  the sole stakeholder with scope, mitigation, and expiry.

**Current conclusion:** Task 1003 is not complete. The protocol and ledger are
ready and F-1003-001 is closed in source. A fresh signed enrollment build is
still required before participant enrollment. Controlled-beta runs, elapsed
multi-day evidence, interviews, and resulting decisions remain external
evidence gates.
