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

## 2026-09-21 — Execute the release CI source gate

Continued task 1004 on `feature/1004-release-ci-evidence` from clean `main`
at `131e171`. Acceptance for this tranche: execute the official manual macOS
release workflow, diagnose any failure before signing, remove environment-
dependent test assumptions, and report only evidence the run actually proves.
Ponytail 4.10.0 (MIT, full mode), agent-adapter, menubar-shell,
security-review, and quality-gates apply. XERJ's loopback listener on port
9200 was absent; the existing adapter and test source were inspected directly.

`rtk gh workflow run release-macos.yml --ref main -R mpakus/cuckoding.com`
created [run 35662057281](https://github.com/mpakus/cuckoding.com/actions/runs/35662057281).
Checkout, pinned OTP/Elixir setup, and pinned-tool installation passed. The
`mix quality` step ran before certificate import but failed two Claude Code
adapter tests: both called `launch_spec/2` or `start/2` without `path`, so the
adapter correctly returned `:not_installed` on a clean runner without the
Claude CLI. Source compilation, format, Credo, Sobelow and dependency audit
were not the failure. Signing, notary preparation, packaging, and upload were
skipped. GitHub currently lists only `APPLE_SIGNING_IDENTITY` and two Tauri
signing secrets; certificate/password and notary key/ID/issuer are still
missing. No secret value was fetched or printed.

The tests now pass their existing executable fixture explicitly for the
launch, no-helper error, start, and resume paths, and assert the fixture is
selected. Production adapter behavior is unchanged. `rtk env -u CR_PAT mix
test test/cuckoding/adapters/claude_code_test.exs` passed (4 tests, zero
failures). `rtk env -u CR_PAT mix quality` passed after the final assertion
(10 properties, 288 tests, zero failures; strict Credo no issues; Sobelow
scan complete; no retired/advisory packages). Fixture crash and transient
SQLite-busy logs were expected tests, not gate failures. A new CI run is still
required; this local pass does not close the frozen-candidate release gate.
`rtk proxy` was used for exact native `lsof`, `who`, `stat`, and `sed` output
where RTK filtering would change inspection semantics; no product command
configuration was changed.

## 2026-09-21 — Rerun release CI after fixture correction

The preceding fixture/doc change was committed as `112473e` and
fast-forwarded/pushed to `main`. `rtk gh workflow run release-macos.yml --ref
main -R mpakus/cuckoding.com` created
[run 35663188771](https://github.com/mpakus/cuckoding.com/actions/runs/35663188771)
at that exact head SHA. The macOS-15 job passed checkout, pinned beam/tool
installation, and `rtk mix deps.get` plus `rtk mix quality`: 10 properties,
288 tests, zero failures; strict Credo found no issues, Sobelow completed,
and Hex found no retired/advisory packages. The five missing names reported
by its value-free preflight were `APPLE_CERTIFICATE`,
`APPLE_CERTIFICATE_PASSWORD`, `APPLE_NOTARY_KEY`, `APPLE_NOTARY_KEY_ID`, and
`APPLE_NOTARY_ISSUER`. It exited 1 before certificate import; no signing,
notarization, updater packaging, artifact upload, or publish occurred.
`rtk gh secret list -R mpakus/cuckoding.com` showed only the existing signing
identity and two Tauri updater secrets; `rtk gh variable list -R
mpakus/cuckoding.com --json name --jq '.[].name'` showed all three public
update variables. These were name-only inspections; no credential values were
read or printed. The job also reported a non-blocking Node 20 deprecation
notice for pinned checkout v4. Its actual outcome is a release-configuration
block, not a passing release. Signed updater, current-source QA-account launch,
clean-Mac install/update/rollback, provider/beta, and retention/consent gates
remain open. This documentation-only follow-up used `rtk git diff --check`;
the Mix suite was not rerun after doc edits.

## 2026-09-21 — Stakeholder handoff for CI release credentials

Continued task 1004 on `feature/1004-release-credential-handoff` from clean
`main` at `f893a35`. Acceptance for this documentation-only tranche: identify
the five missing CI secret sources and their exact names without exposing or
transferring a credential; distinguish the local Apple-ID Keychain profile
from the hosted App Store Connect Team API-key path; keep the signed release
and stakeholder trust decision open. Ponytail 4.10.0 (MIT, full mode),
menubar-shell, security-review, and quality-gates apply.

The terminal GitHub Actions run `35663188771` passed the full source gate and
stopped at the value-free preflight before certificate import. A fresh
`rtk gh secret list -R mpakus/cuckoding.com` still showed only
`APPLE_SIGNING_IDENTITY` and the two Tauri updater secrets. Inspected
`.github/workflows/release-macos.yml` and `desktop/notarize.sh` without
reading secret values. The local `Cuckoding` `notarytool` profile authenticates
with an Apple ID app-specific password; the hosted workflow instead requires
a Developer ID Application identity exported with its private key as a
password-protected `.p12`, and an App Store Connect **Team** API `.p8` key,
key ID, and issuer UUID. The Team ID is not the issuer UUID. Apple Keychain,
App Store Connect, and GitHub Actions primary instructions were checked for
the documented handoff. No export, upload, GitHub secret mutation, or signing
request was performed.

`docs/DISTRIBUTION.md` now gives the stakeholder a safe five-secret checklist
and links to the official source instructions; `docs/RELEASE_READINESS.md`
and `docs/PLAN.md` point to it while retaining the explicit no-go status.
Provisioning credentials on GitHub is a stakeholder trust decision. A local
release path with the existing Keychain profile remains an option if that
transfer is not approved, but it still needs the updater key, complete
artifacts, and all acceptance drills. This documentation does not grant
approval or mark task 1004 complete.

Verification: `rtk git diff --check` and a read-only relative-link check on
the touched Markdown passed. No Mix, Rust, or packaging gate was rerun for
documentation-only changes; the earlier CI source result remains tied to
`112473e`, not this docs commit. `rtk proxy` preserved exact `cat` and
`notarytool --help` output for instruction and native CLI inspection. No
credential value was read or printed. Remaining external gates include the
five CI secrets (or a stakeholder-approved local-only distribution path),
provider-key rotation confirmation, real-provider/beta observations, signed
updater, and clean-Mac acceptance.

## 2026-09-21 — Disclose diagnostics retention before export

Continued task 1004 on `fix/1004-diagnostics-disclosure` from clean `main` at
`920d3d7`. Acceptance for this small privacy tranche: Settings states before
export that a diagnostics ZIP remains local until the owner deletes it and is
not uploaded by Cuckoding; the existing export security boundary and explicit
action remain unchanged; focused and full source checks pass. Ponytail 4.10.0
(MIT, full mode), Elixir/Phoenix LiveView, better-writing,
better-accessibility, menubar-shell, security-review, and quality-gates apply.

Source trace: `Diagnostics.export/1` creates an owner-only ZIP beneath the
application data directory; the LiveView action is explicit; the native shell
only reveals the returned local path. No automatic diagnostics upload or
age-based purge was found. The pre-export UI already listed the bundle's
contents and exclusions but did not say what happened to the generated file
after creation. Added one plain-language paragraph there and two focused
LiveView assertions. The disclosure describes current behavior; it is not a
new retention policy, an upload control, or participant consent. Updated
`docs/RELEASE_READINESS.md`, `docs/PLAN.md`, and task 1004 without closing
their approval or signed-build gates.

Verification: `rtk env -u CR_PAT mix format` passed. `rtk env -u CR_PAT mix
test test/cuckoding_web/plugin_settings_live_test.exs
test/cuckoding/diagnostics_test.exs` passed (6 tests, zero failures). `rtk env
-u CR_PAT mix quality` passed (10 properties, 288 tests, zero failures;
warnings-as-errors compile, strict Credo no issues, Sobelow complete, Hex
audit no retired/advisory packages). The two plugin-supervisor crash logs in
the suite were intentional fixtures. A read-only browser check of the running
`/settings/plugins` page showed the sentence before the **Create diagnostics
bundle** button; no bundle was created in the user's app. `rtk proxy` was
used for complete instruction/source reads where filtering would hide needed
context. `rtk git diff --check` passed and a read-only Ruby check found all
relative links in the touched docs resolve. No migration, provider call,
signing operation, user-data deletion,
or GitHub secret mutation occurred. A signed enrollment build and stakeholder
retention/consent approval remain required.

## 2026-09-21 — Revalidate the latest unsigned developer bundle

Continued task 1004 on `feature/1004-current-source-preflight` from clean
`main` at `a3ef7b1`. Acceptance for this preflight: build that exact source
through the documented developer entry point, run its bundled-release
verifier, identify the resulting signature class, and correct `docs/PLAN.md`
and release documentation that called the older `17d367a` signed ZIP current.
This is not signing, enrollment, or clean-Mac acceptance. Ponytail 4.10.0
(MIT, full mode), menubar-shell, security-review, and quality-gates apply.

The first `rtk env -u CR_PAT ./bin/dev.build` assembled Phoenix and passed
release metadata, Rust tests, and Clippy, but Tauri bundling returned
`Operation not permitted (os error 1)` without a path. The partially created
bundle was ignored build output, not the retained signed candidate. A
controlled direct `cargo-tauri build --bundles app` rerun with the pinned
Rust toolchain, `RUST_BACKTRACE=1`, and `RUST_LOG=debug` succeeded. The
standalone `rtk proxy env -u GEM_HOME -u GEM_PATH
PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/ruby verify.rb` then passed all
sterile startup, authentication, crash, safe-mode, and rollback checks.

To test the actual entry point again, `rtk env -u CR_PAT ./bin/dev.build`
was rerun unmodified and exited 0: production release, metadata/promotion
checks (6 Ruby runs, 15 assertions), Rust format, 10 shell tests, Clippy,
Tauri bundle, and the complete sterile verifier all passed. `rtk proxy
codesign -dv --verbose=2 desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`
reported `Signature=adhoc` and no Team ID. The first bundle error was not
reproduced; its root cause is unconfirmed and remains a packaging-reliability
observation for the frozen release job. No build-script change was justified
by the available evidence.

The docs now label the signed/notarized `17d367a` ZIP as revision-specific
prior evidence and the `a3ef7b1` app as unsigned current-source evidence.
During that unsigned preflight, no provider task, app launch against the
user's data, Apple signing or notarization, CI secret mutation, publication,
or deletion of retained artifacts occurred. `rtk proxy` preserved exact
native Ruby, Cargo, and codesign output; those commands are not product
command configuration.
Documentation checks: `rtk proxy git diff --check` passed, and a read-only
Ruby check confirmed all relative Markdown links in the four touched `docs/`
files resolve. No Mix quality rerun was needed after the documentation-only
edits; the developer build's production compile, Rust checks, and sterile
verifier are tied to the unmodified `a3ef7b1` source.

### Developer ID and same-Mac archive follow-up

The existing Keychain held one valid Developer ID Application identity.
`rtk proxy env CUCKODING_SIGNING_IDENTITY=<identity> sh desktop/sign.sh
<a3ef7b1 app>` signed and strictly verified all 26 Mach-O files, the outer
bundle, hardened runtime, timestamp, matching Team ID, and BEAM JIT
entitlement. The identity was selected by displayed name; no private key
was exported or read. A `rtk proxy ditto -c -k --keepParent` archive of the
signed app was submitted with `rtk proxy env CUCKODING_NOTARY_PROFILE=Cuckoding
sh desktop/notarize.sh <app> <submission.zip> <evidence>`.
Apple accepted submission `9bcbd65e-79f4-43a2-b324-3f49be5c5b1e` with
zero issues; stapling, ticket validation, and Gatekeeper passed. The
embedded release passed `rtk proxy env -u GEM_HOME -u GEM_PATH
PATH=/usr/bin:/bin:/usr/sbin:/sbin CUCKODING_RELEASE_PATH=<signed app release>
/usr/bin/ruby desktop/verify.rb` after signing.

The app was archived **after** stapling as
`desktop/src-tauri/target/release/Cuckoding-local-notary-a3ef7b1.aJWS9F/Cuckoding-a3ef7b1-stapled.zip`.
`rtk proxy shasum -a 256` returned
`242857407ea002472a1f767203d498a85c595d2e7a7fdaa58566704e7f1bd1f5`;
`rtk proxy unzip -tq` found no errors. A separate extraction with an explicit
quarantine attribute passed `rtk proxy xcrun stapler validate`, `rtk proxy
/usr/bin/codesign --verify --deep --strict --verbose=2`, and `rtk proxy
/usr/sbin/spctl --assess --type execute --verbose=4` (`source=Notarized
Developer ID`). Its embedded release passed every sterile verifier check
again. The ZIP was copied only after checking the target did not exist to
`/Users/Shared/Cuckoding-0.1.0-a3ef7b1-stapled.zip`; the copied SHA-256
matched, and mode `-rw-r--r-- mpak staff` permits the existing `qa` account
to read it. Both older staged ZIPs and `desktop/dist/` remain untouched.

This is current-app-source same-Mac evidence, not a complete signed updater,
QA-account launch, clean physical Mac test, participant consent, or beta
enrollment. No shell was launched against the current user's app data; the
sterile verifier used temporary directories. The saved `notarytool` profile
performed the submission without credential values entering source or logs.
Final checks after documentation updates: `rtk proxy git diff --check`
passed; a read-only Ruby relative-link check passed for `docs/PLAN.md`,
`docs/RELEASE_READINESS.md`, `docs/DISTRIBUTION.md`, and
`docs/BETA_REPORT.md`; `rtk env -u CR_PAT mix quality` passed (10 properties,
288 tests, zero failures; strict Credo no issues, Sobelow scan complete,
Hex audit no retired/advisory packages). The two plugin-supervisor crash
logs were intentional test fixtures. These source checks do not substitute
for the still-missing hosted CI, provider, participant, or clean-Mac gates.

## 2026-09-21 — Refresh signed-app evidence after runner fix

Continued task 1004 on `feature/1004-latest-signed-preflight` from clean
`main` at `6ebbd6c`. Acceptance for this tranche: rebuild the exact new
app source (including the process-inspection fix), verify its production
release, sign and notarize without replacing earlier ZIP candidates, test
a quarantined post-staple extraction, and correct `docs/PLAN.md` and the
release ledger to tie claims to the right revision. Do not count this as a
signed updater, QA-account launch, clean-Mac test, beta, or MVP acceptance.
Ponytail 4.10.0 (MIT, full mode), menubar-shell, security-review, and
quality-gates apply. Existing build/sign/notary/sterile scripts are reused;
no new release tooling or credential path is planned.

`rtk env -u CR_PAT ./bin/dev.build` exited 0 for `6ebbd6c`: production
release and metadata checks (6 Ruby runs, 15 assertions), Rust format,
10 shell tests, Clippy, Tauri app bundle, and the sterile release verifier
passed. Before signing, `rtk proxy codesign -dv --verbose=2` identified the
app as ad-hoc without a Team ID. The existing Keychain Developer ID identity
was passed by name to `rtk proxy env CUCKODING_SIGNING_IDENTITY=... sh
desktop/sign.sh <app>`; the script signed and verified all 26 Mach-O files.
No private key value was read or stored in the repository.

The signed app was archived with `rtk proxy ditto -c -k --keepParent` and
submitted through `rtk proxy env CUCKODING_NOTARY_PROFILE=Cuckoding sh
desktop/notarize.sh <app> <submission.zip> <evidence>`. Apple accepted
submission `bf94f6da-a3c4-4bf0-a512-4408599973bc`; the saved log reports
`Accepted` and zero issues. Stapling and Gatekeeper passed. The embedded
release's `desktop/verify.rb` drill passed after signing. A distinct ZIP made
after stapling is retained at
`desktop/src-tauri/target/release/Cuckoding-local-notary-6ebbd6c.waSlcF/Cuckoding-6ebbd6c-stapled.zip`;
`rtk proxy shasum -a 256` returned
`c5f17966f69123c490fb7e048d0476ae5937ed2177d7b936ee653e3787783d1e`,
and `rtk proxy unzip -tq` found no archive errors.

`rtk proxy ditto -x -k` extracted that ZIP into a separate directory and
`rtk proxy xattr -w com.apple.quarantine` marked the exact extracted app.
On that copy, `rtk proxy xcrun stapler validate`, `rtk proxy /usr/bin/codesign
--verify --deep --strict --verbose=2`, and `rtk proxy /usr/sbin/spctl --assess
--type execute --verbose=4` all exited 0; Gatekeeper reported `source=Notarized
Developer ID`. The extracted app's embedded release passed the full sterile
`desktop/verify.rb` startup, token/session, diagnostics, crash, safe-mode,
and update/rollback drill. Its verifier used temporary data directories,
not the current user's live application data.

Only after confirming the destination was absent, `rtk proxy cp -p` staged
`/Users/Shared/Cuckoding-0.1.0-6ebbd6c-stapled.zip`. Its SHA-256 matches
the candidate, `rtk proxy unzip -tq` passes, and its readable file mode is
`-rw-r--r--`. Earlier staged ZIPs and `desktop/dist/` were not replaced.
`rtk proxy` was used for exact native signing, archive, Gatekeeper, and
system-Ruby behavior; it is not a runtime command-policy exception. This is
current app-code same-Mac evidence, not a signed updater, real QA-account
launch, clean-Mac install, participant consent, or beta acceptance.

Documentation checks: `rtk proxy git diff --check` exited 0; a read-only
system-Ruby check found every relative Markdown link in the four changed
`docs/` files resolves. `rtk proxy who` still listed only the current
`mpak` login, so no QA-account launch is claimed. No implementation source
changed in this tranche; the exact `6ebbd6c` app passed `bin/dev.build` and
both pre- and post-archive sterile checks. Hosted CI and real-provider gates
were not rerun for these documentation edits.

## 2026-09-21 — Correct the QA-account evidence ledger

Continued task 1004 on `fix/1004-qa-evidence-accuracy` from clean `main` at
`2dcfab1`. Acceptance: the release matrix must not claim a separate-account
test absent from the task worklog, while retaining the proven same-Mac checks
and the open clean-Mac gate. Ponytail 4.10.0 (MIT, full mode), quality-gates,
and security-review apply; this is evidence wording only.

The release matrix said a prior ZIP passed on a separate account, but this
worklog's QA handoff and later ZIP staging entries explicitly say no QA login
or app launch occurred. The matrix now says the ZIPs are staged, not launched.
No ZIP, credential, application data, or release state was changed.

`rtk proxy git diff --check` passed. A scoped search of the four release
documents found no remaining separate-account pass claim. `rtk proxy who`
listed only `mpak`; `rtk gh secret list -R mpakus/cuckoding.com --json name
--jq '.[].name'` still listed only the existing signing identity and two
updater-key secrets, not the five Apple certificate/notary entries required
by hosted CI. Those checks inspect names/session presence only, not values.
The correction needs no product tests or migration; separate-account, CI,
clean-Mac, provider, and beta acceptance remain open.

## 2026-09-21 — Current-main hosted release source gate

Continued task 1004 on `feature/1004-current-ci-quality-evidence` from clean
`main` at `e96882b`. Acceptance for this tranche: run the official hosted
release workflow against that exact current source, record the source-quality
and value-free configuration-step outcomes, and update `docs/PLAN.md` and the
release ledger without claiming signing or enrollment acceptance. Ponytail
4.10.0 (MIT, full mode), quality-gates, menubar-shell, and security-review
apply. The existing workflow is reused; no release automation is changed.

`rtk gh workflow run release-macos.yml -R mpakus/cuckoding.com --ref main`
created [run 35680103836](https://github.com/mpakus/cuckoding.com/actions/runs/35680103836)
at source SHA `e96882b7de15fbaebf70bfe6eb1c8bf7569eacc7`.
`rtk gh run watch 35680103836 -R mpakus/cuckoding.com --interval 30
--exit-status` observed the same live run through completion (overall exit 1).
The pinned-tool install and **Verify source quality before loading signing
material** steps passed. The scoped quality log showed `10 properties,
289 tests, 0 failures` and `No retired or security advisory packages found`;
the step as a whole exited successfully. The value-free configuration step
then failed on exactly `APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`,
`APPLE_NOTARY_KEY`, `APPLE_NOTARY_KEY_ID`, and `APPLE_NOTARY_ISSUER`.
Certificate import, notarization-key preparation, build/sign/notarize,
and artifact upload were skipped. The run also annotated that pinned checkout
v4 targets Node.js 20 and was forced onto Node.js 24; no checkout failure
occurred, so that compatibility warning is tracked rather than labeled a
release pass or a diagnosed defect. No secret value or job environment was
retrieved; only step conclusions, scoped quality lines, and missing names
were inspected.

Documentation-only checks: `rtk proxy git diff --check` passed, and a
read-only system-Ruby scan found every relative Markdown link in the changed
`docs/` files resolves. No local product test, provider run, or migration was
performed after this CI observation. The hosted source gate is current;
release signing and beta acceptance remain no-go.
