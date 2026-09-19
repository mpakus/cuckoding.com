# Controlled Beta Runbook

This runbook is the evidence protocol for Task 1003. It separates product
evidence from participant administration: the repository contains only
anonymized identifiers and findings. Names, contact details, invitations,
calendar entries, consent records, and repository names stay outside Git.

The sole stakeholder owns recruitment, interviews, and acceptance decisions.
An agent may prepare the protocol and summarize supplied anonymized evidence,
but it must not invent participants, elapsed use, interview answers, or run
results.

## Entry gate

Begin external testing only when all of the following are true:

- the build is identified by a Git SHA and was produced by the documented
  signed build path;
- the supported Claude Code, Codex, and Cursor Agent adapters pass their current conformance
  gates;
- the recovery matrix in `docs/RECOVERY_DRILLS.md` is green;
- outbound product telemetry is off;
- the tester understands that the host runner executes local processes and is
  not a sandbox;
- the selected repository and provider account are authorized for the test;
- no production credential is exposed to an agent process.

Stop immediately if the repository has conflicting user changes, a requested
capability exceeds the approved policy, a secret appears in output or an
artifact, or evidence crosses a project boundary.

## Cohort and coverage

Recruit three to five developers who already run two or more coding agents.
Include, across the cohort, at least one independent developer, one small-team
lead, and one developer responsible for security-sensitive code. Assign only
participant codes `B01` through `B05` in repository evidence.

Exercise at least three authorized repositories, recorded only as `R01`,
`R02`, and `R03`. Together they should cover:

| Required variation | Minimum evidence |
| --- | --- |
| Repository shape | one Elixir/Phoenix repository, one Node or frontend repository, and one mixed or polyglot repository |
| Runtime | one completed default workflow with Claude Code and one with Codex |
| Workflow | happy path, structured QA return to development, and human-approved release handoff |
| Concurrency | two active boards without process, port, worktree, event, or knowledge crossover |
| Interruption | app quit/relaunch and at least one run spanning a real sleep/wake cycle |
| Duration | at least one run remains durable for 24 wall-clock hours or more |
| Knowledge | candidate review, consolidation/publication decision, later retrieval, and usage evidence |

Task 1002 recovery evidence is an entry gate, not a substitute for these beta
observations.

## Safe test setup

1. Choose a repository the tester may use with the selected provider. Remove
   customer data, secrets, private issue text, and production configuration
   before enrollment.
2. Use a dedicated clone or disposable test branch at a recorded starting SHA.
   Never dogfood against the tester's production checkout.
3. Use a dedicated Cuckoding beta data directory and a fresh project record.
   Do not reuse production app data, global runtime configuration, or another
   participant's knowledge namespace.
4. Keep outbound telemetry disabled. Provider runtimes still follow their own
   user-selected network and data policies; disclose that before the run.
5. Confirm the capability preview, allowed paths, command policy, worktree, and
   release target before starting. Do not grant the home directory, SSH keys,
   cloud credentials, Keychain, or unrelated repositories.
6. Seed a bounded, useful task that can be judged from tests and a diff. Avoid
   production deploys, destructive migrations, live credentials, and customer
   data.
7. Before sharing diagnostics, use the product's redacted export, inspect it
   manually, and remove repository-specific source, absolute private paths,
   personal data, and provider payloads not needed for the finding.

The isolation rule adapts Agetor's practice of using dedicated development
data and temporary repositories. Cuckoding additionally requires recorded
capabilities, per-project knowledge boundaries, redaction, and human approval.

### Project-first enrollment

On the dashboard, use **Add project**. Complete the four steps for project
identity, the existing repository and actual base branch, the absolute path to
the pinned Codex or Claude Code executable, and review. Claude Code additionally
requires the already reviewed absolute API key helper path. A dirty working tree
may be registered, but use a dedicated authorized clone for beta execution.

Confirmation registers only the project and its trusted configuration version.
It does not create a board, task, run, branch, worktree, port, or process. Board
creation, task creation, and task start are separate participant actions. Do not
substitute the legacy internal walking-skeleton constructor for those UI steps;
controlled-beta enrollment remains paused until the project workspace and task
start surfaces are complete.

After an explicitly started task creates a run, the Codex run page shows one
complete sign-in command in a read-only field with an adjacent copy button. The
command sets the private run-owned `CODEX_HOME` and runs `login --device-auth`;
the credential remains in that run directory. Run the copied command in
Terminal, complete sign-in, and return to the run page. Choose **Check
authentication and start workflow**. Cuckoding
checks the pinned runtime version and isolated authentication before changing
the durable run from queued to running. Claude Code performs the same start
gate through the reviewed helper. A failed probe leaves the run queued.

For the controlled beta, use an authorized disposable clone whose `origin` is
a local bare repository when exercising release handoff. GitHub handoff exists
behind a trusted policy snapshot and Keychain reference, but project setup
does not create or infer either. Never replace that explicit configuration with
ambient Git or provider credentials.

The enrollment application is distributed through the repository's GitHub
Release. Before creating the version tag, confirm that `desktop/release.sh`
passes locally with the long-lived updater key and `Cuckoding` notarization
profile. A pushed `v*` tag publishes only after the signed build, notarization,
Gatekeeper, updater signature, SBOM, provenance, and checksum gates pass. Record
the release URL, source revision, notarization submission, and artifact digest
in the report before sharing the build.

## Run procedure

For each repository, record the following in `docs/BETA_REPORT.md` before the
run: anonymized repository code and shape, participant code, build SHA, macOS
version, workflow version, runtime, model when known, provider policy choice,
starting repository SHA, and UTC start time.

Then complete these observations:

1. Create a project and default board, inspect the planned worktree and policy,
   and start a bounded task.
2. Observe specification, development, QA, human approval, and release handoff.
   Confirm each long-running state shows elapsed time, owner role, runtime,
   model when known, and a safe control.
3. Force one QA rejection with structured, actionable findings. Confirm the
   run returns to development once and retains the finding and attempt history.
4. Run a second board concurrently. Confirm its worktree, port range, process
   group, events, artifacts, approvals, and knowledge do not appear in the
   first board.
5. During an active stage, allow a real sleep/wake cycle. In a separate
   observation, quit and relaunch Cuckoding. Confirm recovery does not duplicate
   the stage or lose durable state.
6. Review the diff and evidence before approval. Approve release handoff only
   to a disposable or explicitly authorized target; record the resulting branch
   and draft-PR outcome without storing its private URL.
7. Review every knowledge candidate against the rubric below. Exercise one
   accepted item in a later run and confirm the usage record identifies the
   correct project, item version, run, and stage.
8. Record the UTC end time, active and wall time, outcome, relevant evidence
   IDs, and finding IDs. Mark missing evidence as `not observed`, never `pass`.

## Knowledge-quality rubric

Score each reviewed item from 0 to 2 in every dimension. Store only a concise
anonymized explanation and durable evidence identifiers; do not paste private
source or prompts into the report.

| Dimension | 0 | 1 | 2 |
| --- | --- | --- | --- |
| Correctness | false or misleading | partly correct or missing a material caveat | accurate and appropriately qualified |
| Scope | wrong project or overgeneralized | correct project but applicability is vague | exact project and applicability boundary |
| Actionability | unusable | helpful with interpretation | directly usable by a later task |
| Freshness | contradicted or stale | date or validity is unclear | current, dated, and supersession-aware |
| Provenance | evidence cannot support it | evidence exists but is incomplete | specific run, stage, artifact/event, and SHA support it |
| Safety | secret, personal data, or cross-project content | safe but unnecessarily identifying | redacted, minimal, and correctly scoped |

An item passes only when all six dimensions score at least 1, the total is at
least 10 of 12, and Correctness, Scope, Provenance, and Safety each score 2.
A Safety or Scope score of 0 is a critical finding: reject or revoke the item,
stop publication and retrieval for the affected scope, preserve redacted audit
evidence, and investigate before continuing.

## Interview guide

Use one 30-minute conversation per participant. Ask for concrete examples
before presenting Cuckoding or its hypotheses. Do not disclose desired answers.

### Current behavior — 10 minutes

1. Tell me about the last task where you ran two or more coding agents. What
   were you trying to finish?
2. How did you know which agent owned each piece of work?
3. What happened when a run failed, the laptop slept, or you returned later?
4. How did you manage worktrees, terminals, ports, and branches?
5. What evidence did you need before merging, and what was difficult to trust?
6. Which security or privacy concern would stop you from using an orchestrator?

### Observed beta use — 10 minutes

7. Please walk through the run without my help. Where do you expect to act
   next, and why?
8. Which status or control is unclear, missing, or unnecessary?
9. What would you verify outside Cuckoding before approving this change?
10. Would the recovery and knowledge history change how you work? Why or why
    not?

### Hypotheses — 10 minutes

Read the positioning statement from `docs/MVP_BOUNDARY_AND_POSITIONING.md`,
then ask:

11. In your own words, what problem does this product solve? Who is it not for?
12. Which launch runtimes must it support for you? Which can wait?
13. Compare the names `Runstead`, `Branchyard`, and `Agent Harbor`. What does
    each imply? Suggest a name only if none fits.
14. What would you expect from an Apache-2.0 local core? Which paid boundary
    would feel fair or unfair?
15. At what point would the proposed Community, $20/month Pro, or future
    $40/user/month Teams options become worth paying for? What do you use or
    pay today?
16. What is the strongest reason you would not adopt this product?

After each interview, write only anonymized observations, verbatim phrases no
longer than needed, contradictions, and resulting decisions. Separate what was
observed from stakeholder interpretation.

## Finding triage and exit gate

| Severity | Definition | Required action |
| --- | --- | --- |
| Critical | secret exposure, unauthorized path/process/network action, data loss, cross-project contamination, release without approval, or unrecoverable durable-state corruption | stop affected testing; close and retest, or record sole-stakeholder acceptance with scope, rationale, mitigation, owner, and expiry |
| High | core workflow cannot complete or recovery duplicates/loses work | close before MVP release and retest the original observation |
| Medium | material usability, evidence, accessibility, or knowledge-quality defect with a workaround | assign an owner and release disposition |
| Low | polish or minor friction that does not threaten trust or completion | backlog with evidence |

Task 1003 exits only after the coverage matrix is evidenced, 3–5 interviews
are summarized, knowledge quality is scored, every finding has a disposition,
and all critical findings are closed or explicitly accepted by the sole
stakeholder. A percentage or general impression cannot replace a missing
required observation.
