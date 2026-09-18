# Dogfood and Controlled Beta Report

**Task:** 1003

**Status:** prepared; external beta not started

**Last updated:** 2026-09-18

**Owner:** sole stakeholder

This is the anonymized evidence ledger for `docs/BETA_RUNBOOK.md`. It does not
contain participant names, contact details, calendar information, repository
names, private URLs, source code, prompts, secrets, or unredacted diagnostics.
Blank rows mean `not observed`; they are not passing evidence.

## Pre-beta gate

| Gate | Status | Evidence or action |
| --- | --- | --- |
| Deterministic and physical recovery matrix | pass | Task 1002, 27/27 observations; this is prerequisite evidence and does not count as a beta run |
| Signed and notarized build identified | pending | record build SHA and notarization evidence before enrollment |
| Claude Code adapter conformance | pass for current fixture contract | 2026-09-18 focused adapter suite; real beta use still requires separately verified run-scoped authentication |
| Codex adapter conformance | pass for current fixture contract | 2026-09-18 focused adapter suite; real beta use must use the run-scoped home |
| Outbound product telemetry off | pending | verify on the enrolled build |
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
| — | — | No beta findings recorded yet | — | pending beta | — | — |

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
- [ ] Claude Code and Codex each complete a default workflow.
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
ready, but controlled-beta runs, elapsed multi-day evidence, interviews, and
resulting decisions remain external evidence gates.
