# 1004 — MVP release readiness

Claimed on `fix/1004-resource-retention` from clean `main`. Task 1003 is
still in progress, so this is an independent preflight of one task-1004 gate,
not release acceptance. Acceptance for this tranche: automatic retention must
not delete measured resource samples while an active stage still needs them
for its durable stage aggregate; completed stages may be pruned only after
their aggregate exists; focused regression and quality checks pass; `docs/`
and `docs/PLAN.md` distinguish verified behavior from remaining beta gates.

Ponytail 4.10.0 (MIT, full mode), observability, security-review, and
quality-gates apply. XERJ project search was unavailable because the loopback
node on port 9200 is not running; inspected the source and tests directly.
The current `ResourceRollups.maintain/1` computes finished-stage rollups and
then deletes all samples older than seven days, including samples of an
unfinished long-running stage. Such a stage could later finish with a partial
aggregate. This is a local-data accuracy risk, not an outbound telemetry issue.

The change gates automatic raw deletion on an existing durable stage rollup,
using the existing stage/session relationship in a SQL subquery. It adds no
new table, worker, setting, or dependency. A focused regression holds one
stage open across eight days, confirms no sample is pruned, then finishes it
and confirms maintenance writes a full stage aggregate before deleting the
aged raw row. Direct stage aggregation now rejects unfinished stages as well,
so an incidental caller cannot create a provisional rollup that would make
those raw samples eligible for pruning. `rtk env -u CR_PAT mix test
test/cuckoding/telemetry/resource_metrics_test.exs` passed (5 tests, 0
failures). Static source inspection found no automatic product telemetry HTTP
client: local resource sampling writes SQLite; diagnostics export and shell
update checks are explicit user actions. That is code-level preflight only,
not outbound-network evidence from a signed enrollment build. Minute rollup
backfill after long downtime remains unproven, so the broad retention and
consent gate stays open in task 1004 and `docs/BETA_REPORT.md`.

Final checks: `rtk env -u CR_PAT mix format` passed;
`rtk env -u CR_PAT mix test
test/cuckoding/telemetry/resource_metrics_test.exs` passed again (5 tests,
0 failures) after the unfinished-stage guard. `rtk env -u CR_PAT mix quality`
passed (10 properties, 283 tests, 0 failures; Credo 0 issues; Sobelow scan
complete; Hex audit found no retired/advisory packages). The two
plugin-supervisor crash logs were intentional test fixtures. No migration,
external network operation, or user data deletion was performed by this
change. Residual risk: minute rollups missed during long app downtime are not
yet backfilled; stage totals remain protected by the new pruning guard.

## 2026-09-21 — Catch up missed minute rollups before pruning

Continued task 1004 on `fix/1004-minute-rollup-catchup` from clean `main`.
Acceptance for this tranche: maintenance finds completed minutes missed during
an app outage; work is bounded per tick and resumes from durable rows after
restart; raw samples cannot be pruned until both minute and finished-stage
aggregates exist; an eight-day synthetic outage and backlog regression pass;
and docs/PLAN report the resulting evidence without calling the signed beta
gate complete. No migration or provider operation is intended.

Ponytail 4.10.0 (MIT, full mode), observability, security-review, and
quality-gates apply. XERJ project search was unavailable on loopback port
9200; inspected `ResourceRollups.maintain/1`, `prune/2`, the current indexes,
and the focused tests directly. A read-only SQLite parameter probe was
insufficient to infer Ecto's column encoding; the focused fixture confirmed
stored UTC timestamps include `Z`, so catch-up uses that exact minute key for
indexed rollup lookup.

Implementation: maintenance queries missing completed session-minute buckets
against the existing unique rollup index, ordered oldest first with a limit
of 120 per tick. No process-local cursor or new table is needed: the next
tick/restart selects whatever durable buckets remain. Automatic raw pruning
now requires both the minute rollup and the finished-stage rollup, so a
failed or incomplete catch-up never destroys its source rows. The first
focused run exposed a timestamp-format mismatch in the SQL fragment; a
synthetic fixture showed the actual stored `Z` suffix, and the query was
corrected before acceptance. Tests cover an eight-day interruption, a
121-minute backlog across repeated maintenance calls, idempotent repeat
calls, and refusal to prune a finished-stage sample lacking its minute
rollup. Removed the unused `prune_raw/1` helper, which bypassed the safe
aggregate guard and was only called from one test. This is synthetic local
evidence, not a signed-build observation. The lookup can scan retained raw
rows; the 120-bucket cap bounds aggregation, not query cost. Profile that scan
with beta-sized data before raising throughput claims.

Verification: `rtk env -u CR_PAT mix format` passed;
`rtk env -u CR_PAT mix test
test/cuckoding/telemetry/resource_metrics_test.exs` passed (7 tests, 0
failures). `rtk env -u CR_PAT mix quality` passed (10 properties, 285 tests,
0 failures; Credo 0 issues, Sobelow scan complete, Hex audit found no
retired/advisory packages). Expected plugin-supervisor crash fixtures and
transient SQLite lock retries appeared in the suite output; no test failed.
`rtk git diff --check` passed. No migration, signed build, paid provider
invocation, or deletion of the user's existing app data was performed.

## 2026-09-21 — Reconcile MVP disclosures with current source

Continued task 1004 on `fix/1004-current-boundary-docs` from clean `main`.
Acceptance for this documentation tranche: the launch-adapter list, local
retention defaults, provider credential locations, public working name, and
repository license must match current source and artifacts; README,
`docs/PLAN.md`, and the beta ledger must make the same distinctions. This does
not close participant, signed-build, or real-provider acceptance.

Ponytail 4.10.0 (MIT, full mode), menubar-shell, security-review, and
quality-gates apply. The source check found Claude Code, Codex, and Cursor
Agent in the runnable adapter list; automatic age pruning in resource metrics
only; a bounded process-output preview plus the full redacted artifact; and an
Apache-2.0 `LICENSE` already in the repository. The boundary document still
claimed only two launch adapters, 30-day output/payload deletion, Keychain-only
secrets, an internal-only name, and no license file. Correct the disclosures
without claiming that implementation, signing, beta consent, or legal review
has been accepted.

Documentation now distinguishes implemented launch adapters from accepted
provider workflows; corrects the false 30-day output/payload purge; describes
provider-owned file credentials separately from app-managed Keychain secrets;
and reconciles the public working name and existing Apache-2.0 license. The
new `docs/RELEASE_READINESS.md` is a current-source operator guide and explicit
no-go report for support, onboarding, host limits, privacy/data, recovery, and
troubleshooting. It links to the detailed runbook rather than inventing a
release artifact or support SLA. `docs/PLAN.md`, README, beta ledger, and task
1004 reflect the same status.

Verification: `rtk gh secret list --repo mpakus/cuckoding.com --json name
--jq '.[].name'` showed only `APPLE_SIGNING_IDENTITY` and the two Tauri updater
secrets; the Apple certificate/password and notary key/ID/issuer remain absent.
`rtk env -u CR_PAT ruby -e ...` inspected names only and found every local
release variable required by `docs/DISTRIBUTION.md` unset; it printed no
values. `rtk env -u CR_PAT mix test
test/cuckoding/telemetry/resource_metrics_test.exs` passed (7 tests, 0
failures). A read-only Ruby link check found all 13 relative links in the new
readiness guide resolve. `rtk git diff --check` passed. Source searches found
the metric-only automatic age pruning and no automatic outbound product
telemetry client. No behavioral code, migration, signed build, provider call,
or user data was changed; compiler/full-suite gates were not rerun for this
documentation-only tranche. No RTK proxy exception was needed.

Residual gates: approve artifact retention/participant disclosure; confirm
rotation of the prior exposed provider key; run authenticated workflows and
controlled beta; configure signing/notary inputs; freeze one candidate and
verify its install/update/rollback/uninstall, checksums, SBOM, provenance, and
release notes on a clean supported Mac. Task 1004 and Phase 10 remain open.

## 2026-09-21 — Definition-of-done evidence audit

Continued task 1004 on `fix/1004-dod-evidence-audit` from clean `main` at
`6a4cd90`. Acceptance for this tranche: inspect each explicit MVP
definition-of-done item against current tests, worklogs, beta evidence, and
artifact state; record exactly what is proved and what is not; correct any
checkbox whose evidence is narrower than its wording; keep the overall task
and release no-go until a single frozen candidate has matching acceptance.

Ponytail 4.10.0 (MIT, full mode), quality-gates, menubar-shell, and
security-review apply. Task 1002's 27/27 observations are real recovery-drill
evidence, including physical sleep, but the stage worker in that drill is a
fixture. It does not prove a complete current-source delivery task on the
signed enrollment build across hibernate, quit/relaunch, and real sleep. The
marked-complete DoD item in `docs/PLAN.md` is therefore too broad and must be
reopened. The focused DoD matrix in `docs/RELEASE_READINESS.md` will retain the
drill result as prerequisite evidence without converting it into product
acceptance.

Audited each of the ten criteria against the task-0405 real Codex/local-bare
demo, task-1002 recovery drills, task-1020 deterministic Review routing,
Agent Floor/accounting/plugin worklogs, task-1003 blank beta ledger, and the
current artifact status. The matrix names the specific missing observation
for each criterion. It reopens only the previously checked integrated recovery
criterion; no historical drill result was changed or discarded. Task 1004's
"every item re-run" gate remains unchecked because the matrix is an audit,
not completion of the missing observations.

`rtk env -u CR_PAT mix quality` passed on source revision `6a4cd90` (10
properties, 285 tests, zero failures; strict Credo no issues, Sobelow scan
complete, no retired/advisory dependencies). The two plugin-supervisor crash
logs were intentional fixtures. This checks source health, not beta or release
behavior. No provider task, signing operation, migration, or user-data change
was performed.

`rtk ruby -e ...` verified all 22 relative links in
`docs/RELEASE_READINESS.md` resolve. `rtk git diff --check` passed. The change
touches only the DoD matrix, its beta/task references, one corrected plan
checkbox, and this worklog; no RTK proxy exception was needed.

## 2026-09-21 — Gate the official release job on source quality

Continued task 1004 on `fix/1004-release-quality-gate` from clean `main` at
`f20935f`. Acceptance for this tranche: the official macOS release job runs
the repository's pinned full Elixir quality alias before any Apple signing or
notary material is imported, and a failure prevents packaging/publication.
Keep local source quality distinct from signed-artifact and clean-Mac evidence;
update `docs/`, `docs/PLAN.md`, and the release ledger accordingly.

Ponytail 4.10.0 (MIT, full mode), quality-gates, menubar-shell, and
security-review apply. Source trace: `.github/workflows/release-macos.yml`
sets up OTP/Elixir and RTK, then imports signing material before calling
`desktop/release.sh`; `desktop/build.sh` runs Rust format/test/clippy and the
sterile shell verifier, but no `mix quality` gate. The release workflow is the
only path that publishes tags, so a single pre-secret step there is the
smallest release-boundary fix. It does not broaden secret access or claim a
completed signed candidate.

Added a single `rtk mix deps.get` / `rtk mix quality` step after pinned build
tools and before certificate import. GitHub Actions' default fail-fast step
ordering means a failing quality command cannot reach signing or the dependent
publish job. A read-only `rtk ruby -ryaml -e ...` check parsed the workflow and
asserted the quality step precedes certificate import, notary-key preparation,
and packaging; it passed. `rtk git diff --check` passed. The current app source
had already passed `rtk env -u CR_PAT mix quality` at `f20935f` (10 properties,
285 tests, zero failures); this workflow-only change was not exercised on a
GitHub macOS runner. An actual tag/manual release job remains blocked by
missing Apple signing/notary secrets and cannot be marked accepted. No secret
value was read or printed, no provider or signing service was called, and no
user data or release artifact was changed. No RTK proxy exception was needed.
