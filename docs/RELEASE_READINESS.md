# MVP Release Readiness

**Review date:** 2026-09-21  
**Decision:** No-go for controlled-beta enrollment or public MVP release.

This is the current-source operator guide and decision record for task 1004,
not acceptance of an installed release candidate. The evidence ledger is
[BETA_REPORT.md](BETA_REPORT.md); the exact build and update procedure is
[DISTRIBUTION.md](DISTRIBUTION.md). Revisit this decision against one frozen,
signed artifact after task 1003 has completed.

## Support matrix and limits

| Surface | Current contract | Acceptance still needed |
| --- | --- | --- |
| Host | Apple Silicon macOS; bundle declares macOS 13.0 minimum; single local user | Fresh signed/notarized build installed and exercised on a clean supported Mac |
| UI | Menubar shell opens loopback-only Phoenix LiveView in the default browser | Critical journey and accessibility on the enrollment build |
| Execution | Supervised host processes in distinct Git worktrees; **not a sandbox** | Real-provider runs, detached-process review, and multi-board isolation |
| Agents | Claude Code, Codex, Cursor Agent launch adapters implemented; Codex/Cursor saved profiles use app-owned provider credentials | Default workflow, restart/refresh, revocation, and cross-project/concurrent execution with real provider accounts |
| Setup-only agents | OpenCode and Custom Agent may be saved, but cannot launch tasks | Reviewed adapters and conformance before promising execution |
| Updates | Signed updater with backup/rollback checks in source and prior-host evidence | Current frozen artifact, update, rollback, and uninstall on a clean Mac |

Provider CLIs, Git, and optional plugin binaries are discovered on the user's
Mac, not promised inside the bundle. The host runner cannot hard-enforce
filesystem, network, CPU, or memory isolation; review provider permissions and
the run's effective grant before starting. See
[EXECUTION_ENVIRONMENTS.md](EXECUTION_ENVIRONMENTS.md) and
[TRUSTED_HOST_THREAT_MODEL.md](TRUSTED_HOST_THREAT_MODEL.md).

## Onboarding and normal operation

1. Install only a signed/notarized candidate whose source revision, checksum,
   updater signature, and release notes match the enrollment record. No such
   current-source candidate has been accepted yet.
2. Open **Agents** and authorize each provider account once in its app-owned
   profile. Select each named agent's model. Attaching a saved agent to another
   project reuses compatible sign-in, but provider expiry remains authoritative.
3. Use **Add project** to select a local folder and base branch in the native
   chooser. Review before confirmation; an empty or unborn folder is initialized
   only after confirmation. Existing uncommitted work may be registered, but
   run preparation needs a clean committed base.
4. In project settings, attach agents and assign Specifications, Coding, and
   Review roles. Create a board, then a Draft task. Mark it Ready, **Prepare
   run**, check agent sign-in, and explicitly start the workflow. A board
   planning prompt instead creates proposals for human review; it does not
   silently import tasks or start delivery work.
5. Monitor the dashboard, task, and run pages. A blocked or failed delivery
   task can use **Retry with a new run**; the old worktree and evidence remain,
   and uncommitted old-worktree changes are not copied. Release push/PR and
   global knowledge publication require separate human approval.

Board role assignments and run snapshots are immutable copies: editing a
project does not rewrite existing boards or historical runs. See
[FLOW.md](FLOW.md), [CONFIGURATION.md](CONFIGURATION.md), and
[AGENT_AUTHORIZATION_FLOW.md](AGENT_AUTHORIZATION_FLOW.md).

## Privacy, data, and consent

- Projects, workflow history, approvals, and artifact metadata live in local
  SQLite; project knowledge is local Markdown. There is no automatic outbound
  product analytics or crash-report client. Provider CLIs, explicit update
  checks, and approved VCS handoff have their own network behavior.
- Process output is redacted before persistence. The UI preview is bounded,
  but the full redacted artifact and any persisted diagnostic payload fragments
  have **no automatic age purge**. Do not promise deletion after 30 days.
- Resource samples become eligible for pruning after seven days only when
  their minute and finished-stage rollups exist; rollups are eligible after
  30 days. Actual behavior on the enrollment build remains unobserved.
- App-managed secrets use Keychain references. Saved Codex/Cursor credentials
  are provider-owned in private app-owned file profiles; Cuckoding does not
  read or export their values. Provider expiry and revocation still apply.
- Diagnostics export is explicit, owner-only, size-bounded, and excludes
  source, prompts, raw logs, provider output, credentials, argv, and private
  paths. Its contents are described in [DISTRIBUTION.md](DISTRIBUTION.md).

Before beta enrollment, approve a participant-facing artifact-retention and
cleanup policy, verify it on the signed build, and record host-runner/provider
disclosure and consent in [BETA_REPORT.md](BETA_REPORT.md). Until then, this
section is a disclosure of current source, not completed consent.

## Backup, recovery, and troubleshooting

Signed updates snapshot database, knowledge, and configuration before
schema changes and retain the failed database if rollback is needed. Direct
replacement of an unsigned developer bundle is different: quit first, make
and verify a SQLite online backup, snapshot project knowledge/configuration,
run only matching forward migrations, and retain the backup through inspection.
Follow [DEVELOPMENT.md](DEVELOPMENT.md) and
[DISTRIBUTION.md](DISTRIBUTION.md); never delete a run folder or reset a
database to make an error disappear.

| Symptom | First safe action |
| --- | --- |
| Saved agent needs sign-in | Open **Agents**, re-authorize the named account, then retry the queued run's check. Do not copy provider token files into a run. |
| Run preparation says repository is dirty | Commit or stash in the registered repository, then prepare again; inspect the old worktree separately. |
| Task or run is blocked/failed | Open its timeline, safe failure code, and redacted logs. Retry from the task only after checking the previous process is stopped. |
| Application cannot start after an update | Use safe mode and the retained backup/failed database evidence; do not downgrade onto an unknown schema. |
| Evidence is needed for support | Export the bounded diagnostics bundle explicitly, review it locally, and share it only through an approved channel. |

The sole stakeholder owns controlled-beta intake and go/no-go decisions.
Public support channel, incident response owner, service level, and artifact
retention approval are not finalized; do not imply production support. Treat
credential exposure, unauthorized host action, data loss, or cross-project
contamination as a critical stop and preserve sanitized evidence under the
[beta finding process](BETA_RUNBOOK.md).

## Definition-of-done evidence audit

The ten items in [PLAN.md](PLAN.md) are product acceptance criteria, not a
count of passing unit tests. At source revision `6a4cd90`, `rtk env -u CR_PAT
mix quality` passed (10 properties, 285 tests, zero failures; strict Credo,
Sobelow, and dependency audit clean). That verifies the current source gate,
not any unobserved provider, participant, or installed-build behavior.

| MVP criterion | Evidence in hand | Still required to close it |
| --- | --- | --- |
| Two runtimes complete the default workflow | [Walking-skeleton record](../worklog/2026-09-17-0405-walking-skeleton.md) has an older real Codex demo; adapter fixtures cover current contracts | Two supported providers complete the current default workflow with isolated, reusable authentication on the frozen build |
| Two boards execute without crossover | Scheduler and workflow tests cover admission and scoped records; beta isolation rows remain `not observed` | Concurrent D03 board runs; inspect worktrees, ports, process groups, events, artifacts, approvals, and knowledge |
| A task survives hibernate, quit/relaunch, and real sleep once per stage | [Task 1002](../worklog/2026-09-18-1002-recovery-drills.md) passed 27/27 named drills, including physical sleep, with fixture stage workers | Integrated delivery task on the current build across the full sequence; D04 and D05 record run/stage IDs and duplicate-execution check |
| Agent Floor attributes every action | [Agent Floor tests](../worklog/2026-09-17-0604-agent-floor.md) cover a ten-session fixture and durable read model | Inspect attribution for real concurrent provider work on the candidate; unresolved or unowned actions fail this gate |
| Cost provenance and active/wall time are clear | [Accounting tests](../worklog/2026-09-17-0603-usage-cost.md) cover labels, formulas, and unavailable cost | Inspect provider-reported versus estimated/unavailable values and both clocks on real D01–D03 runs |
| Failed QA routes structured findings | [Task 1020](../worklog/2026-09-20-1020-review-reroute-local-completion.md) covers deterministic reroutes and attempt budget | D02 real-provider Review rejection returns to the responsible stage with finding and attempt history |
| Human approval performs release handoff | The [walking skeleton](../worklog/2026-09-17-0405-walking-skeleton.md) pushed an approved branch to a local bare remote | D01 approved handoff on an authorized target, including a draft PR; verify no push before approval |
| Knowledge is reviewed and later used | Knowledge extraction/publication/lineage tests and views exist | Score K01–K03 and show one approved item used by a later real run with project, version, run, and stage provenance |
| Four reference plugins enable, contribute, and degrade safely | [Task 0803](../worklog/2026-09-18-0803-reference-plugins.md) records fixture conformance | Exercise RTK, XERJ, Ponytail, and read-only MCP in the enrolled app with labeled contributions and removal without core failure |
| Clean Mac installs, runs, updates, and uninstalls | A prior-revision signed ZIP passed on a separate account; the current-source unsigned app passed its sterile verifier | One current signed/notarized candidate on a clean supported Mac, including sample task, update, rollback, and uninstall with data checks |

None of these ten criteria has matching current-release acceptance evidence
yet. The checked recovery item in the prior plan overstated task 1002's scope;
it is reopened while retaining the 27/27 prerequisite result. The beta IDs
above refer to the blank, not-observed rows in [BETA_REPORT.md](BETA_REPORT.md),
not completed runs. Do not copy a pass between revisions, providers, or
fixtures without matching artifact and observation IDs.

## Decision and required evidence

The previous signed ZIP is from an older source revision. A current-source
unsigned developer app passed a sterile verifier, and simulated recovery
passed, but neither is signed enrollment or clean-Mac acceptance. The release
workflow now places `mix quality` before loading signing material; this ordering
has not yet been exercised for the frozen candidate. Two non-resolving pinned
release actions were repaired and all five refs now resolve upstream; the
job still has no frozen-candidate run. The release
CI still lacks the Apple certificate/password and notary key/ID/issuer secrets;
the release job now reports missing names before certificate import, but has
not executed. Local release variables were absent at this review. GitHub's
`macos-15` runner label is Apple Silicon and matches the script's host check.
The prior provider key exposure also awaits stakeholder confirmation of rotation before more paid
provider work. Controlled-beta runs, interviews, and real-provider lifecycle
evidence remain missing. These are independent no-go gates, not warnings that
can be cleared by this documentation review.

For release, attach the frozen revision, signed/notarized installer and updater
artifacts, checksums, SBOM, provenance, release notes, clean-Mac install/update/
rollback/uninstall evidence, completed beta ledger, and explicit sole-stakeholder
decision. Keep this document at no-go until each item is verified against that
same artifact; use [PLAN.md](PLAN.md) for the full MVP definition of done.
