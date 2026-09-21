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

## 2026-09-21 — Repair non-resolving release action pins

Continued task 1004 on `fix/1004-release-action-pins` from clean `main` at
`298b60e`. Acceptance for this tranche: every action pinned in the official
release workflow resolves to an upstream commit; replacement pins keep the
same intended major action and required input contract; no secret values,
release artifact, or provider action is touched. Update the release evidence
and plan without claiming that the workflow has completed.

Ponytail 4.10.0 (MIT, full mode), quality-gates, menubar-shell, and
security-review apply. Read-only GitHub API checks found that checkout,
upload-artifact, and download-artifact SHAs resolve, but the pinned
`erlef/setup-beam` and `apple-actions/import-codesign-certs` SHAs return 422
"No commit found". The tagged upstream replacements are `setup-beam@v1.24.1`
at `54075bcc5e249e4758d363f27d099f55d843f124` and
`import-codesign-certs@v7.0.0` at
`5142e029c445c10ffc7149d172e540235a065466`. Their pinned `action.yml`
files confirm strict OTP/Elixir version inputs, Hex/Rebar defaults, and the
existing PKCS#12 base64/password input names. Two pin substitutions are the
smallest root-cause correction.

Replaced those two refs without changing action inputs. Read-only
`rtk gh api repos/<owner>/<repo>/commits/<sha> --jq .sha` probes returned the
exact requested SHA for all five workflow actions (four build, one publish).
`rtk ruby -ryaml -e ...` parsed the workflow, found four 40-character pinned
build-job refs, and confirmed the quality step still precedes certificate
import. `rtk git diff --check` passed. This verifies references and ordering,
not action execution or notarization. Missing Apple secrets and the absence of
a frozen candidate still prevent a release-job acceptance claim. No RTK proxy
exception was needed.

## 2026-09-21 — Release configuration preflight

Continued task 1004 on `fix/1004-release-config-preflight` from clean `main`
at `5653872`. Acceptance for this tranche: the official release job reports
each missing required Apple/updater secret or public update variable by name,
without printing values, before certificate import or release packaging; a
missing item fails the job. Preserve the source-quality-before-secret ordering,
update `docs/` and `docs/PLAN.md`, and distinguish structural/local checks from
an unrun signed-release job.

Ponytail 4.10.0 (MIT, full mode), quality-gates, menubar-shell, and
security-review apply. GitHub's current runner-image table identifies
`macos-15` on GitHub Actions as Apple Silicon, matching `desktop/release.sh`;
no runner-label change is needed. Read-only repository metadata shows no
`release-macos` run and only the signing identity plus the two updater-key
secrets configured. The certificate and notary credentials remain external
release blockers; the preflight improves the failure path but cannot supply
them.

Added one Bash step after `mix quality` and before certificate import. Its
environment maps the existing eight required secrets and three public update
variables, tests each for nonempty content without printing any value, reports
all missing names using GitHub error annotations, and exits nonzero if any
are absent. No credential values were inspected or changed. The only new
capability is an early validation read of the same values the subsequent
signing steps already require; secret-bearing subprocesses and logs remain
unchanged.

Focused check: `rtk proxy ruby -ryaml -ropen3 -e 'w = YAML.load_file(".github/workflows/release-macos.yml"); steps = w.fetch("jobs").fetch("release").fetch("steps"); names = steps.map { |s| s["name"] || s["uses"] }; quality = names.index("Verify source quality before loading signing material"); check = names.index("Check release configuration"); signing = names.index { |n| n.start_with?("apple-actions/import-codesign-certs@") }; raise "ordering" unless quality < check && check < signing; step = steps.fetch(check); required = %w[APPLE_CERTIFICATE APPLE_CERTIFICATE_PASSWORD APPLE_SIGNING_IDENTITY APPLE_NOTARY_KEY APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER TAURI_SIGNING_PRIVATE_KEY TAURI_SIGNING_PRIVATE_KEY_PASSWORD CUCKODING_UPDATE_ENDPOINT CUCKODING_UPDATE_BASE_URL CUCKODING_UPDATER_PUBLIC_KEY]; raise "env mismatch" unless step.fetch("env").keys.sort == required.sort; env = required.to_h { |name| [name, "dummy"] }.merge("PATH" => ENV.fetch("PATH"), "HOME" => ENV.fetch("HOME")); out, err, status = Open3.capture3(env, "bash", "-c", step.fetch("run"), unsetenv_others: true); raise "configured preflight failed: #{out} #{err}" unless status.success? && out.empty? && err.empty?; env.delete("APPLE_CERTIFICATE"); env.delete("APPLE_NOTARY_KEY"); out, err, status = Open3.capture3(env, "bash", "-c", step.fetch("run"), unsetenv_others: true); raise "missing-name preflight failed" unless status.exitstatus == 1 && out.include?("APPLE_CERTIFICATE") && out.include?("APPLE_NOTARY_KEY") && !out.include?("dummy") && err.empty?; puts "release preflight structure and missing-name behavior passed"'` passed. It exercises a fully configured dummy environment and two missing names without any real secret.

`rtk git diff --check` passed. No `mix quality` rerun is claimed for this
workflow/docs-only change; the prior source gate and the actual GitHub release
job remain distinct evidence. No RTK proxy exception was needed.

## 2026-09-21 — Current-revision developer build and event-sequence gate

Continued task 1004 on `fix/1004-event-sequence-gate` from clean `main` at
`3246b3b`. Acceptance for this tranche: rebuild and verify the current-source
unsigned developer app, run the full quality gate, and resolve any gate failure
without changing event durability or weakening the concurrent-writer property.
Update `docs/` and `docs/PLAN.md` with only the observed scope; signed and
clean-Mac acceptance remain open.

Ponytail 4.10.0 (MIT, full mode), quality-gates, menubar-shell, and
security-review apply. XERJ search against `cuckoding-project-v7` could not
connect to its loopback node; the source and test were inspected directly.
`rtk ./bin/dev.build` passed from `3246b3b`: production Phoenix release,
release metadata checks, 10 Rust tests, app bundling, and the sterile verifier
including startup/authentication, crash cleanup, safe mode, and update/rollback
drills. Free disk space remained above 13 GiB. This is an unsigned developer
build on the same Mac, not a notarized beta artifact or clean-machine install.

`rtk env -u CR_PAT mix quality` failed with one of 10 properties and 285 tests:
`EventStorePropertyTest`'s eight-writer case timed out in `Task.await_many/2`
at 10,000 ms after `BEGIN IMMEDIATE` lock retries; format, compile, Credo,
Sobelow, and Hex audit passed. `rtk env -u CR_PAT mix test --seed 603399`
reproduced the same timeout. The focused property with that seed passed;
`--trace` passed it serially. A separate 10-round, eight-writer exercise
completed 80 appends in 41–156 ms per round. `EventStore` permits three
5,000 ms SQLite busy waits before its bounded begin retry is exhausted, so
the property's 10,000 ms task wait can expire before the supported retry path
returns. The next check will align that assertion window with the configured
retry ceiling and re-run the full gate; if writes still fail, investigate the
lock holder rather than masking the failure.

Changed only the property's await window from 10 to 20 seconds, covering
three configured five-second SQLite busy waits plus scheduling headroom. The
assertion still requires every writer to return `{:ok, ...}` and verifies the
exact gapless sequence afterward; production transaction/retry logic is
unchanged. A controlled test-database probe held `BEGIN IMMEDIATE` for
11 seconds and then released it: the event append succeeded after 11,050 ms,
demonstrating that the old assertion deadline could fail a valid bounded
retry. The probe printed no application secrets and changed no user database.

The bounded-contention probe command was:

```sh
rtk env MIX_ENV=test mix run -e 'Ecto.Adapters.SQL.Sandbox.mode(Cuckoding.Repo, :manual); {:ok, lock} = Exqlite.Sqlite3.open("cuckoding_test.db"); :ok = Exqlite.Sqlite3.execute(lock, "BEGIN IMMEDIATE"); started = System.monotonic_time(:millisecond); task = Task.async(fn -> Ecto.Adapters.SQL.Sandbox.unboxed_run(Cuckoding.Repo, fn -> Cuckoding.Execution.EventStore.append(Ecto.UUID.generate(), %{event_type: "test.contention", public_summary: "Contention check", payload: %{}}) end) end); Process.sleep(11_000); :ok = Exqlite.Sqlite3.execute(lock, "COMMIT"); :ok = Exqlite.Sqlite3.close(lock); result = Task.await(task, 20_000); IO.inspect({System.monotonic_time(:millisecond) - started, match?({:ok, _}, result)}, label: "bounded contention")'
```

Verification: `rtk env -u CR_PAT mix test --seed 603399` passed (10 properties,
285 tests, zero failures); `rtk env -u CR_PAT mix quality` passed on seed
367943 (10 properties, 285 tests, zero failures, strict Credo clean, Sobelow
scan complete, no retired/advisory dependencies). `rtk git diff --check`
passed. The former failure did not reproduce after the assertion change; a
signed/notarized build and controlled beta were not run. No RTK proxy
exception was needed.

## 2026-09-21 — Current-source local signing drill

Continued task 1004 on `feature/1004-current-local-signing` from clean `main`
at `fca8770`. Acceptance for this tranche: verify the current app bundle's
Developer ID signature and hardened runtime using the existing signing
script; retain the older `desktop/dist/` untouched; if the saved notary
profile works, notarize and staple only this local app candidate and record
the response ID, issue count, and Gatekeeper result. Update `docs/` and
`docs/PLAN.md` without claiming a signed updater, published release, clean-Mac
install, or controlled beta.

Ponytail 4.10.0 (MIT, full mode), quality-gates, menubar-shell, and
security-review apply. `rtk git status --short --branch` was clean on main;
`rtk proxy security find-identity -v -p codesigning` found one valid Developer
ID Application identity for team G4HV2FL5N2. The local app is the developer
build produced from `3246b3b` (only a test-only commit followed), and
`rtk proxy /usr/bin/codesign --display --verbose=4` showed it was ad hoc
signed with no TeamIdentifier. `rtk proxy xcrun notarytool history
--keychain-profile Cuckoding --output-format json` succeeded, confirming the
saved profile is accessible without printing credentials. The older signed
`desktop/dist/` is present and excluded from this drill. Free space is about
12 GiB; the candidate and evidence will stay in ignored build directories.

The executed build-boundary commands were:

```sh
rtk proxy env 'CUCKODING_SIGNING_IDENTITY=Developer ID Application: Renat Ibragimov (G4HV2FL5N2)' sh desktop/sign.sh
rtk proxy ditto -c -k --keepParent /Users/mpak/www/elixir/cuckoding.com/desktop/src-tauri/target/release/bundle/macos/Cuckoding.app /Users/mpak/www/elixir/cuckoding.com/desktop/src-tauri/target/release/Cuckoding-local-notary.KaGOlp/Cuckoding-notary.zip
rtk proxy env CUCKODING_NOTARY_PROFILE=Cuckoding sh desktop/notarize.sh /Users/mpak/www/elixir/cuckoding.com/desktop/src-tauri/target/release/bundle/macos/Cuckoding.app /Users/mpak/www/elixir/cuckoding.com/desktop/src-tauri/target/release/Cuckoding-local-notary.KaGOlp/Cuckoding-notary.zip /Users/mpak/www/elixir/cuckoding.com/desktop/src-tauri/target/release/Cuckoding-local-notary.KaGOlp/evidence
rtk proxy env -u GEM_HOME -u GEM_PATH PATH=/usr/bin:/bin:/usr/sbin:/sbin CUCKODING_RELEASE_PATH=/Users/mpak/www/elixir/cuckoding.com/desktop/src-tauri/target/release/bundle/macos/Cuckoding.app/Contents/Resources/release/bin/cuckoding /usr/bin/ruby desktop/verify.rb
```

Signing passed: all 26 Mach-O files
received valid hardened-runtime Developer ID signatures with matching team
and secure timestamps; BEAM's JIT entitlement was verified. The app now has
identifier `com.cuckoding.desktop`, TeamIdentifier `G4HV2FL5N2`, a stapled
ticket, and no ad-hoc shell signature.

The local candidate directory is ignored
`desktop/src-tauri/target/release/Cuckoding-local-notary.KaGOlp/`.
`ditto` created only the submission archive. Notarization passed: Apple accepted submission
`02d108c6-87f9-4b31-b515-28444fa98938` with zero issues, the ticket was
stapled and validated, and `spctl` reported `source=Notarized Developer ID`.
The notarization response and log remain in that ignored candidate directory;
no credential value was printed. The first ad-hoc JSON inspection accidentally
used system Ruby with ambient RVM gems and failed to parse the newer `json`
gem; the release scripts already clear `GEM_HOME`/`GEM_PATH`. Repeating the
read-only evidence summary with `rtk proxy env -u GEM_HOME -u GEM_PATH
PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/ruby -rjson -e ...` succeeded and
reported `Accepted`, `issues=0`. This diagnostic environment failure did not
affect signing or notarization.

The signed embedded release passed every sterile startup, auth, crash,
safe-mode, and update/rollback check against the signed embedded release.
`desktop/dist/` retained its 2026-09-18 content; no updater signature or
complete post-staple release archive was produced, and no clean-account or
clean-Mac install occurred. The local app evidence narrows the signing risk
but cannot close task 1004's full release gate.

`rtk git diff --check` passed for the documentation and worklog update. RTK
proxy was used for codesign, `ditto`, `notarytool`, `spctl`, and the sterile
Ruby subprocess so their unfiltered output and binary behavior were preserved;
all repository commands remained RTK-prefixed. The notarization upload was
the normal Apple release-validation side effect authorized by the MVP goal;
there was no GitHub release, push of an artifact, credential export, or data
cleanup.

## 2026-09-21 — Fresh archive from the stapled app

Continued task 1004 on `feature/1004-stapled-zip-smoke` from clean `main` at
`62569f3`. Acceptance for this tranche: package the already-stapled local app
into a new ignored ZIP, extract that exact archive to a separate directory,
verify the extracted app's ticket, Gatekeeper assessment, code signature, and
embedded-release sterile checks, and record a checksum. Keep the older
`desktop/dist/` untouched. This same-Mac smoke must not be described as a
clean-Mac install, signed updater, complete release package, or beta enrollment.

Ponytail 4.10.0 (MIT, full mode), quality-gates, menubar-shell, and
security-review apply. The prior goal turn verified the already-implemented
task retry in the live UI and passed its 9 focused tests; this tranche returns
to the open release-readiness objective. `rtk git status --short --branch`
showed a clean main branch before the branch was created. `rtk proxy` will be
used for exact macOS archive, signature, Gatekeeper, and verifier behavior and
recorded below.

`rtk proxy ditto -c -k --keepParent` archived the stapled app into
`desktop/src-tauri/target/release/Cuckoding-local-notary.KaGOlp/Cuckoding-0.1.0-macos-arm64-stapled.zip`
and `rtk proxy ditto -x -k` extracted it to the separately created
`extracted.PswQPy/` directory. `rtk proxy unzip -tq` found no compressed-data
errors. `rtk proxy shasum -a 256` returned
`171529c3d4ee18970b04f0f6fc66fe9ccea2a8158ba4c270b645af220eadcd3c`.
Only the extracted copy was given `com.apple.quarantine`; `rtk proxy xattr -p`
confirmed the attribute. This manually applied attribute is not proof of a
browser download or clean-machine launch.

For that extracted app, `rtk proxy xcrun stapler validate` passed; `rtk proxy
/usr/bin/codesign --verify --deep --strict --verbose=4` found it valid on disk
and satisfying its designated requirement; `rtk proxy /usr/sbin/spctl --assess
--type execute --verbose=4` accepted it as `Notarized Developer ID`. The
exact embedded release passed `rtk proxy env -u GEM_HOME -u GEM_PATH
PATH=/usr/bin:/bin:/usr/sbin:/sbin CUCKODING_RELEASE_PATH=<extracted
app>/Contents/Resources/release/bin/cuckoding /usr/bin/ruby
desktop/verify.rb`: all emitted startup, authentication, diagnostics, crash,
safe-mode, and update/rollback checks were `PASS` with exit 0. The verifier
uses temporary test data; it did not launch a user project or modify the live
application database.

`desktop/dist/` still contains the September 18 distribution files; the new
ZIP is only an ignored local candidate. `rtk git diff --check` passed after
the documentation update, and `rtk ruby -e ... docs/PLAN.md
docs/RELEASE_READINESS.md docs/DISTRIBUTION.md` confirmed all relative links
in the changed docs resolve. This docs-only tranche did not rerun Mix quality;
the extracted release verifier is the proportionate artifact check. `rtk proxy` preserved exact native archive, xattr,
signature, Gatekeeper, checksum, and verifier behavior/output. No credentials
were read or printed, no release artifact was published, and the remaining
signed-updater, clean-Mac, real-provider, beta, and retention-consent gates
are unchanged.

## 2026-09-21 — Separate-account smoke handoff

Continued task 1004 on `feature/1004-qa-account-handoff` from clean `main` at
`763d0ed`. Acceptance for this tranche: determine whether the signed menubar
app can be launched without touching the current user's live data; if not,
make the verified post-staple ZIP available to the existing QA macOS account
and document a safe, checksum-bound test handoff. Do not claim a clean-account
or clean-Mac result before that account actually runs the app.

Ponytail 4.10.0 (MIT, full mode), menubar-shell, security-review, and
quality-gates apply. `desktop/src-tauri/src/main.rs:107` uses
`app.path().app_data_dir()` and immediately creates/opens the account's app
data, database, and log. No reviewed disposable-data override is present.
Starting the signed shell as the current user would therefore risk migrating
or modifying the existing application database and was deliberately skipped.
The existing `qa` account is UID 502; `rtk proxy sudo -n -u qa id` required
an administrator password, and `rtk proxy launchctl asuser 502 /usr/bin/id`
returned `Operation not permitted`. No privilege or account state was changed.

The signed ZIP contains a public distribution binary, not a credential
bundle. `rtk proxy cp -p` staged it at
`/Users/Shared/Cuckoding-0.1.0-3246b3b-stapled.zip`, readable by the QA
account. `rtk proxy shasum -a 256` returned the same
`171529c3d4ee18970b04f0f6fc66fe9ccea2a8158ba4c270b645af220eadcd3c`
as the local candidate; `rtk proxy unzip -tq` found no errors. This copies no
user data, never launches the app, and leaves `desktop/dist/` untouched.
The sole stakeholder must log into the QA account (or explicitly authorize
privileged execution) for the real menubar/browser smoke. Do not send an
administrator password to Codex. `rtk proxy` was used for native identity,
archive, checksum, and account checks so exact output/semantics were retained.
`rtk git diff --check` and the `rtk ruby -e ...` relative-link check over
`docs/PLAN.md`, `docs/RELEASE_READINESS.md`, and `docs/DISTRIBUTION.md` passed.
No Mix, Rust, provider, or release-job check was rerun for this documentation
and local-file-staging tranche; the signed ZIP's earlier verifier result is
recorded above and was not mislabeled as a new app launch.

## 2026-09-21 — Current-source isolated signed app

Continued task 1004 on `feature/1004-current-build` from clean `main` at
`17d367a`. Acceptance for this tranche: build the latest source in a separate
checkout, verify the bundled release, sign and notarize the app, then verify
a newly archived, quarantined extraction without replacing the older signed
distribution or touching the live application database. Ponytail 4.10.0
(MIT, full mode), quality-gates, menubar-shell, and security-review apply.

The managed worktree at
`/Users/mpak/.codex/worktrees/phase10-current-build/cuckoding.com` kept all
build outputs separate. `rtk proxy sh desktop/build.sh` passed: production
Phoenix release, release-metadata/promote tests, Rust format, 10 shell tests,
Clippy, Tauri bundle, and the sterile release verifier. `rtk proxy` preserved
the exact native build/test and verifier output. The verifier passed startup,
one-time browser handoff, auth rejection/audit, diagnostics, shutdown/crash
cleanup, safe mode, and update/rollback checks. It used temporary test data.

The installed Developer ID identity was discovered by name only; no private
key was read. `rtk proxy env CUCKODING_SIGNING_IDENTITY=... sh desktop/sign.sh
<app>` signed and strictly verified 26 Mach-O files. `rtk proxy ditto -c -k
--keepParent <app> <notary.zip>` created a submission archive, then `rtk proxy
env CUCKODING_NOTARY_PROFILE=Cuckoding sh desktop/notarize.sh <app>
<notary.zip> <evidence>` returned Accepted with zero issues for submission
`4d7775e9-32da-4815-b4d9-e624a7fb27d6`. Stapler validation and
Gatekeeper acceptance passed. `rtk proxy env -u GEM_HOME -u GEM_PATH
PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/ruby desktop/verify.rb` passed
again after signing.

`rtk proxy ditto` archived the stapled app as
`Cuckoding-17d367a-stapled.zip` under the ignored local candidate. `rtk proxy
shasum -a 256` returned
`bcfa5afccc7740a4dbb9ba9178a8032ae58889172b97d3467612967c1d983a07`;
`rtk proxy unzip -tq` found no archive errors. The ZIP was extracted to a
separate ignored directory, given a quarantine attribute, and passed `rtk
proxy xcrun stapler validate`, `rtk proxy /usr/bin/codesign --verify --deep
--strict --verbose=2`, and `rtk proxy /usr/sbin/spctl --assess --type execute
--verbose=4` (`source=Notarized Developer ID`). The **extracted embedded
release** passed `rtk proxy env -u GEM_HOME -u GEM_PATH
PATH=/usr/bin:/bin:/usr/sbin:/sbin CUCKODING_RELEASE_PATH=<extracted
app>/Contents/Resources/release/bin/cuckoding /usr/bin/ruby
desktop/verify.rb` with every check PASS, exit 0.

No provider work, shell launch against the current user's app data, release
publication, updater signing, QA account login, or deletion occurred. The
prior `desktop/dist/` and staged QA ZIP remain untouched. This evidence
updates `docs/PLAN.md`, `docs/DISTRIBUTION.md`, and
`docs/RELEASE_READINESS.md`; the signed-updater, complete release metadata,
clean-Mac, consent/retention, real-provider and beta gates remain open.

Final read-only checks: `rtk proxy /usr/bin/plutil -extract status raw -o -
<candidate>/evidence/notarization-submission.json` returned `Accepted`;
`rtk proxy env -u GEM_HOME -u GEM_PATH
PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/ruby -rjson -e 'puts
Array(JSON.parse(File.read(ARGV.fetch(0)))["issues"]).length'
<candidate>/evidence/notarization-log.json` returned `0`; `rtk git diff
--check` passed. An initial direct system-Ruby JSON check inherited an
incompatible RVM `json` gem and exited 1; clearing `GEM_HOME`/`GEM_PATH` as
the release script does produced the valid zero-issue result above. No
notarization was repeated for that diagnostic command.

The current public binary ZIP was also copied with `rtk proxy cp -p` to
`/Users/Shared/Cuckoding-0.1.0-17d367a-stapled.zip` after a read-only
nonexistence check. `rtk proxy shasum -a 256` returned the same
`bcfa5afccc7740a4dbb9ba9178a8032ae58889172b97d3467612967c1d983a07`;
`rtk proxy unzip -tq` found no errors; `rtk proxy stat -f '%Sp %Su %Sg'`
showed `-rw-r--r-- mpak staff`, readable to the existing QA account. The older
staged ZIP and `desktop/dist/` were not replaced. No login or app launch under
the QA account occurred, so separate-account acceptance is still unverified.
Final documentation checks: `rtk git diff --check` passed; a read-only
`rtk proxy env -u GEM_HOME -u GEM_PATH PATH=/usr/bin:/bin:/usr/sbin:/sbin
/usr/bin/ruby -e ... docs/PLAN.md docs/DISTRIBUTION.md
docs/RELEASE_READINESS.md` relative-link check returned `relative links
present`. This tranche did not rerun the full Mix quality suite because it
changed only task/docs/worklog text; the production compile, shell tests,
Clippy, and three sterile verifier passes are tied to the exact built commit.
