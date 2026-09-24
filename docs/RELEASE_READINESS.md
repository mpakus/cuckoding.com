# MVP Release Readiness

**Review date:** 2026-09-24 (documentation/source delta review; no new release acceptance)

**Decision:** No-go for controlled-beta enrollment or public MVP release.

This is the current-source operator guide and decision record for task 1004,
not acceptance of an installed release candidate. The evidence ledger is
[BETA_REPORT.md](BETA_REPORT.md); the exact build and update procedure is
[DISTRIBUTION.md](DISTRIBUTION.md). Revisit this decision against one frozen,
signed artifact after task 1003 has completed.

## Recent source and packaging status

At this review, local `main` and the local `origin/main` tracking ref both point
to `25c00d3`. Tasks 1034–1036 provide the pearl application design and the
separate Pages design with Classic/Irony artwork; Irony is the Pages default.
Task 1034 records an unsigned native rebuild and local launch. Its historical
PID/port is not evidence of what is running now. No live Pages deployment or
current all-instance restart was verified by this documentation review.

Task 1037 executable discovery was subsequently merged into local main at
`5fa55bc`; a rebuilt native bundle containing it is still pending. It checks CLI locations and Codex Desktop bundles with manual override.
Discovery does not reuse desktop credentials or extend the Codex `0.146.0`
compatibility pin. Real-provider lifecycle and clean-Mac acceptance remain open.

The accepted default roles are now Speculator, Implementor and Reviewer, with
Reviewer revisions returning through Cuckoding to Speculator. Task 1038 implements these names and routes for new defaults, passes the latest
specification between roles, and preserves legacy workflow snapshots.
Executable custom workflows and role-permission editing also remain open; see
[role alignment](PLAN.md#role-contract-alignment--2026-09-24). This requirement
update does not change the no-go decision or close any beta criterion.

## Support matrix and limits

| Surface | Current contract | Acceptance still needed |
| --- | --- | --- |
| Host | Apple Silicon macOS; bundle declares macOS 13.0 minimum; single local user | Fresh signed/notarized build installed and exercised on a clean supported Mac |
| UI | Menubar shell opens loopback-only Phoenix LiveView in the default browser | Critical journey and accessibility on the enrollment build |
| Execution | Supervised host processes in distinct Git worktrees; **not a sandbox** | Real-provider runs, detached-process review, and multi-board isolation |
| Agents | Claude Code, Codex, Cursor Agent launch adapters implemented; Codex/Cursor saved profiles use app-owned provider credentials | Default workflow, restart/refresh, revocation, and cross-project/concurrent execution with real provider accounts |
| Setup-only agents | OpenCode and Custom Agent may be saved, but cannot launch tasks | Reviewed adapters and conformance before promising execution |
| Updates | Signed updater with backup/rollback checks in source and prior-host evidence | Current frozen updater artifact, update, rollback, and uninstall on a clean Mac |

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
   Review roles. Create a board, or explicitly apply saved agents to an
   existing board. Add Draft tasks and mark only eligible work Ready. For a
   manual run, use **Prepare run**, check sign-in, and start the workflow. For
   automatic admission, review the project limits and use **Start project**;
   it admits Ready delivery tasks up to those limits, not Draft tasks or
   proposals. A board planning prompt still requires human review and import.
5. Monitor the dashboard, task, and run pages. A blocked or failed delivery
   task can use **Retry with a new run**; the old worktree and evidence remain,
   and uncommitted old-worktree changes are not copied. Release push/PR and
   global knowledge publication require separate human approval. A passing
   Review still needs a human local-completion or release decision; Start
   project does not make the whole board hands-off.

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
  paths. Settings now says before export that the local bundle stays until the
  owner deletes it and is not uploaded by Cuckoding. Its contents are described
  in [DISTRIBUTION.md](DISTRIBUTION.md).

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
| Agent executable is unknown or rejected | In a build containing task 1037, use **Find automatically** or enter an absolute executable path. A found file must still pass the adapter version check and app-owned sign-in; see [discovery limits](AGENT_AUTHORIZATION_FLOW.md#executable-discovery). |
| Run preparation says repository is dirty | Commit or stash in the registered repository, then prepare again; inspect the old worktree separately. |
| Task or run is blocked/failed | Open its timeline, safe failure code, diagnostic location when recorded, and redacted logs. A location is not a cause; older events may not have one. Retry from the task only after checking the previous process is stopped. |
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
count of passing unit tests. On 2026-09-21, the unsigned developer app rebuilt
from `3246b3b` passed the sterile verifier, including startup, crash, safe-mode,
and rollback drills. A subsequent test-only event-sequence timeout correction
passed `rtk env -u CR_PAT mix quality` (10 properties, 285 tests, zero failures;
strict Credo, Sobelow, and dependency audit clean). These verify local source
and developer-build gates. The local app was then Developer ID signed,
notarized, stapled, Gatekeeper-accepted, and its embedded release passed the
same sterile verifier. A newly archived, quarantined extracted copy also
passed ticket, strict-signature, Gatekeeper, and sterile checks on this Mac.
Then-current `17d367a` source has since passed the same isolated build, signing,
notarization, post-staple extraction, and sterile checks; see
[DISTRIBUTION.md](DISTRIBUTION.md) for its distinct digest and submission ID.
On 2026-09-21, newer `a3ef7b1` source passed `bin/dev.build`, Developer ID
signing, Apple notarization, post-staple ZIP extraction under quarantine,
Gatekeeper, and the embedded-release sterile verifier; see
[DISTRIBUTION.md](DISTRIBUTION.md) for its distinct digest and submission ID.
After the process-inspection fix, then-current `6ebbd6c` passed the same build,
signing, notarization, quarantined ZIP, Gatekeeper, and embedded-release
checks; its revision-specific digest and submission ID are also recorded there.
Then-current app code `d7a6222` subsequently passed the same local checks and has
a distinct staged ZIP; neither copy has been launched by the QA account.
None of this verifies provider, participant, complete release-package, or
clean-Mac install behavior.

| MVP criterion | Evidence in hand | Still required to close it |
| --- | --- | --- |
| Two runtimes complete the default workflow | [Walking-skeleton record](../worklog/2026-09-17-0405-walking-skeleton.md) has an older real Codex demo; adapter fixtures cover current contracts | Two supported providers complete the current default workflow with isolated, reusable authentication on the frozen build |
| Two boards execute without crossover | Scheduler tests cover admission; a deterministic two-board integration test overlaps Development and verifies distinct branches, worktrees, artifacts, markers, and event correlation. D03 remains `not observed` | Concurrent real-provider D03 board runs on the enrolled app; inspect ports, process groups, approvals, knowledge, and all scoped evidence |
| A task survives hibernate, quit/relaunch, and real sleep once per stage | [Task 1002](../worklog/2026-09-18-1002-recovery-drills.md) passed 27/27 named drills, including physical sleep, with fixture stage workers | Integrated delivery task on the current build across the full sequence; D04 and D05 record run/stage IDs and duplicate-execution check |
| Agent Floor attributes every action | [Agent Floor tests](../worklog/2026-09-17-0604-agent-floor.md) cover a ten-session fixture and durable read model | Inspect attribution for real concurrent provider work on the candidate; unresolved or unowned actions fail this gate |
| Cost provenance and active/wall time are clear | [Accounting tests](../worklog/2026-09-17-0603-usage-cost.md) cover labels, formulas, and unavailable cost | Inspect provider-reported versus estimated/unavailable values and both clocks on real D01–D03 runs |
| Failed QA routes structured findings | [Task 1020](../worklog/2026-09-20-1020-review-reroute-local-completion.md) covers deterministic reroutes and attempt budget | D02 real-provider Review rejection returns to the responsible stage with finding and attempt history |
| Human approval performs release handoff | The [walking skeleton](../worklog/2026-09-17-0405-walking-skeleton.md) pushed an approved branch to a local bare remote | D01 approved handoff on an authorized target, including a draft PR; verify no push before approval |
| Knowledge is reviewed and later used | Knowledge extraction/publication/lineage tests and views exist | Score K01–K03 and show one approved item used by a later real run with project, version, run, and stage provenance |
| Four reference plugins enable, contribute, and degrade safely | [Task 0803](../worklog/2026-09-18-0803-reference-plugins.md) records fixture conformance | Exercise RTK, XERJ, Ponytail, and read-only MCP in the enrolled app with labeled contributions and removal without core failure |
| Clean Mac installs, runs, updates, and uninstalls | Signed ZIPs were staged for the QA account without observed launch there; the historical `d7a6222` app and post-staple ZIP passed same-Mac signature, Gatekeeper, and sterile checks | One complete signed/notarized release and updater candidate on a clean supported Mac, including sample task, update, rollback, and uninstall with data checks |

None of these ten criteria has matching current-release acceptance evidence
yet. The checked recovery item in the prior plan overstated task 1002's scope;
it is reopened while retaining the 27/27 prerequisite result. The beta IDs
above refer to the blank, not-observed rows in [BETA_REPORT.md](BETA_REPORT.md),
not completed runs. Do not copy a pass between revisions, providers, or
fixtures without matching artifact and observation IDs.

## Decision and required evidence

The retained `desktop/dist/` ZIP is from an older source revision. The `3246b3b`
developer app passed local Developer ID signing and Apple notarization
(submission `02d108c6-87f9-4b31-b515-28444fa98938`, zero issues), stapling,
Gatekeeper, and a post-signing sterile check of its embedded release. A fresh
post-staple ZIP was extracted, marked with a quarantine attribute, and passed
ticket, strict-signature, Gatekeeper, and embedded-release checks on this Mac;
its SHA-256 is recorded in [DISTRIBUTION.md](DISTRIBUTION.md). This is not a
complete signed release package: no current updater bundle/signature, release
metadata, installed clean-Mac test, or beta enrollment is attached.
The `3246b3b`, `17d367a`, `a3ef7b1`, `6ebbd6c`, and checksum-matched `d7a6222` ZIPs are staged
in `/Users/Shared` for the existing `qa` macOS account, but a real
menubar/browser launch from that account is not yet observed. Running the
signed shell as the current user would use the live
account-derived app data directory; no disposable override is established.
The historical `d7a6222` post-staple ZIP has not been published and still lacks a signed
updater and complete release metadata. A first local Tauri bundle attempt
for the prior `a3ef7b1` returned `Operation not permitted`; a
controlled bundle rerun and then the complete `bin/dev.build` both passed.
The cause of the isolated failure is unconfirmed, so packaging reliability
remains an acceptance concern until the frozen release job succeeds.
The release workflow places `mix quality` before loading signing material.
Its first [manual CI run](https://github.com/mpakus/cuckoding.com/actions/runs/35662057281)
on `131e171` installed the pinned tools and reached source quality, but failed
two Claude adapter tests because their fixtures relied on a locally installed
Claude CLI. After the explicit-fixture fix, the second
[manual run](https://github.com/mpakus/cuckoding.com/actions/runs/35663188771)
on `112473e` passed `mix quality` (288 tests, 10 properties, strict Credo,
Sobelow, and dependency audit). A fresh
[earlier main run](https://github.com/mpakus/cuckoding.com/actions/runs/35680103836)
on `e96882b` passed `mix quality` (289 tests, 10 properties, zero failures)
before its value-free preflight again reported exactly five absent secrets:
`APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`,
`APPLE_NOTARY_KEY`, `APPLE_NOTARY_KEY_ID`, and `APPLE_NOTARY_ISSUER`.
The release checkout pin was subsequently updated to official Node 24-native
v5.1.0. Its [branch CI run](https://github.com/mpakus/cuckoding.com/actions/runs/35681124404)
executed checkout and passed the same source gate (289 tests, 10 properties);
the configuration step still refused those five absent secrets.
The [then-current-main manual run](https://github.com/mpakus/cuckoding.com/actions/runs/35684138654)
on `734128f` passed pinned tool setup and `mix quality` (290 tests, 10
properties, zero failures), then stopped at the same value-free preflight.
Certificate import, notarization, updater signing, and artifact upload were
skipped. The three public update variables and existing updater secrets are
configured, but no credential value was inspected. Local release variables
were absent at that earlier review. The [CI credential handoff](DISTRIBUTION.md#ci-credential-handoff)
explains the stakeholder decision and exact secret sources; the local
`notarytool` profile does not satisfy the hosted workflow. GitHub's
`macos-15` runner label is Apple Silicon and matches the script's host check.
The previously reported provider-key rotation was stakeholder-confirmed on
2026-09-23 without inspecting the secret; see [BETA_REPORT.md](BETA_REPORT.md).
That attestation does not establish provider execution or waive project gates.
Controlled-beta runs, interviews, and real-provider lifecycle
evidence remain missing. These are independent no-go gates, not warnings that
can be cleared by this documentation review.

For release, attach the frozen revision, signed/notarized installer and updater
artifacts, checksums, SBOM, provenance, release notes, clean-Mac install/update/
rollback/uninstall evidence, completed beta ledger, and explicit sole-stakeholder
decision. Keep this document at no-go until each item is verified against that
same artifact; use [PLAN.md](PLAN.md) for the full MVP definition of done.
