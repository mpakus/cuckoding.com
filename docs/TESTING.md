# Verification and acceptance

R050f regressions additionally cover no-command Start, task/final review without
fabricated command receipts, correction and missing-evidence blocking, a required
inspection tool receipt, unchanged configured-command gates, legacy snapshot
refusal, and preservation of generated criteria in automatic cards. Native planning
fixtures assert verification instructions use the same no-tools scratch grant.
See [R050f evidence](../worklog/2026-10-13-R050f-task-verification.md).

## R050e execution evidence

Exercise `test/cuckoding/battles_test.exs`, `battle_executor_test.exs`, `battle_checks_test.exs`, `native_helper_test.exs` and `test/cuckoding_web/battle_live_test.exs`. Cover a two-task dependency chain, failed checks and forced review return, exact candidate/model/criteria binding, stale Start, frozen edit refusal, late results, cancellation uncertainty and restart without replay. Native battle tests verify branch chaining and original checkout preservation; check tests must separately prove the actual macOS sandbox and owned process cleanup without provider inference. Fixture success is not live provider acceptance. See the [R050e worklog](../worklog/2026-10-13-R050e-arena-loop.md) for actual commands/results and omissions.

R010 has current foundation checks; see its [worklog](../worklog/2026-10-06-R010-local-foundation.md)
and [runnable commands](DEVELOPMENT.md#quality-and-bundled-smoke). Later slice
and full-story gates remain open. Historical test counts do not establish proof.

The R050e native check canary is also explicit and uses no account/model:

```sh
rtk proxy env CUCKODING_TEST_CODEX=/absolute/trusted/codex CUCKODING_TEST_RTK=/absolute/trusted/rtk CUCKODING_TEST_CHECK_HELPER=/absolute/built/Cuckoding.app/Contents/MacOS/ccoding cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked project_checks::tests::offline_single_process_sandbox_canaries -- --ignored --exact
```

It verifies eleven scenarios against the selected packaged helper: process
limits, timeout/cancellation, output/source bounds, protected and foreign paths,
peer signal refusal, and cleanup after supervisor death across exec. Re-run when
the grant or native helper changes. A routine ignored result is not a pass.

## Gates by slice

R020m real sandbox check (no account/inference) is opt-in:
`rtk proxy env CUCKODING_TEST_CODEX=/absolute/trusted/codex CUCKODING_ISOLATION_CANARY=fixture cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked isolation::tests::real_codex_two_workspace_isolation -- --ignored`.
Use a verified `0.162.0-alpha.17.2` executable. Routine Cargo tests deliberately
skip this gate; record its separate result. It does not close model-tool execution
or independent review acceptance. Domain/UI regressions live in
`test/cuckoding/isolation_test.exs` and `test/cuckoding_web/isolation_live_test.exs`.

| Slice | Smallest required evidence |
| --- | --- |
| R002 / R040k | Registration/default-board atomic rollback and replay, frozen team, unchanged folder, immediate navigation, existing/empty/multiple boards without GET writes, Advanced and draft disclosure keyboard behavior, live form preservation, honest disabled Start and responsive rendering |
| R040l/m | Bounded folder inventory/snapshots, excluded/link/secret canaries, limits/truncation/identity drift, empty-folder brief, automatic graph import, duplicate/late results, rollback/restart and reanalysis preserving user edits |
| R050d/e | One bounded Start, contextual admission/Git consent, automatic worktree preparation and card movement, forced independent review return through Speculator, exact-candidate evidence and no routine per-task prompts |
| R010 | Clean migration + prior-data isolation, event/command idempotency, shell authentication/replay/loopback, graceful Quit |
| R015 | Static links/assets/scope, motion and denied-storage behavior, desktop/narrow/keyboard inspection; [commands](SITE.md#preview-and-checks) |
| R017 | Brand export reproducibility, four three-layer scenes, alpha, crossing weapons, all-layer pause/reduced motion, desktop/narrow rendering and renamed bundle smoke |
| R020a | Executable confirmation/identity, version allowlist, bounded/split/malformed output, clean environment, timeout/cancellation/descendants, durable interruption and prior-schema upgrade |
| R020b | Bounded RPC, private profile/config, model pages/cursors/validation, stale retention/age, account separation, cancellation, prior-schema copy and real signed-out inspection |
| R020c | Consent/invalidation, official URL validation and session redirect, matching completion, profile exclusion, cancel/cleanup, uncertain restart, real login start/cancel and packaged UI |
| R020d | Usage consent, fresh identity/catalog binding, effective grant preflight, model/thread/turn matching, early completion, tool refusal, cancellation/no replay, closed receipts/canaries, reconnect UI and packaged smoke; real signed-in responses remain separate |
| R020e | Profile checkbox persistence through clock/PubSub, unchecking, setup/submission/reconnect reset, stale form/revision and expired-session refusal, packaged mouse/keyboard proof without provider actions |
| R020f | Full-list flag on every page, visible/hidden entries, malformed visibility, retained old/stale catalogs, all Agents/Team options, shared diagnostic/planning preflight and real read-only refresh |
| R020g | Consume only the submitted profile confirmation; preserve unrelated selections; hide connected/pending sign-in; metadata-only desktop choice; bounded alpha versions and exact allowlist; initial account notification vs later drift; real desktop catalog with private sign-in |
| R020h | Four-step wizard, scoped action forms, optional test consent, live selection retention, durable/revisioned/idempotent model Save, stale review rejection, Team filtering with old bindings retained, informational runtime notices vs requests/account drift |
| R020 | Adapter parsing/cancellation/canaries, model-cache persistence/failure, real login + isolated execution across two workspaces |
| R030a | Seed/immutable history, command replay, competing revisions, bounded roles, confirmed removal, stale/missing/drifted bindings, expired sessions, draft preservation/browser revision guard, fresh/prior-schema package smoke |
| R030b | Confirmed scoped adoption, stale/default revision guards, active-plan exclusion, command replay/atomic events, immutable past receipts/drafts, component session expiry, preserved forms and prior-schema/restart package proof |
| R030 | Team revision inheritance, custom role grants, model/auth separation, historical snapshot immutability |
| R040a | Native chooser/select/cancel/parent loss, bounded protocol, confirmed/idempotent registration, unchanged folders, protected/replaced/duplicate identities, frozen team revision, reconnect/expired session, fresh/prior-schema bundle smoke |
| R040 | Init refusal/consent, initial-commit preview, path confinement, file-task provenance, dependency cycles, custom column gates |
| R040b | Frozen Arena-to-Tabula team, immutable task receipts/history, command replay, atomic event rollback, stale/foreign IDs, draft-only stage gates, recovered/dirty forms, desktop/narrow UI and fresh/prior-schema package smoke |
| R040d | Exact selected-byte/empty first commit, mode/hash/branch/config drift, existing index/refs refusal, path/link/credential guards, metadata bounds, retained partial staging, fresh scoped consent, cancellation/no replay, packaged browser and restart |
| R040c | Fresh scoped init consent, unchanged files/index/history, missing/unborn/committed real Git fixtures, unsafe config/layout refusal, directory identity, deadlines/cancel/descendants, no interrupted replay, expired sessions, packaged desktop/narrow flow and fresh/prior-schema smoke |
| R040e | Frozen Speculator/consent binding, strict structured proposals, tool/model/scope refusal, once-only draft imports/provenance, cancellation/no replay, preserved forms/reconnect, packaged fixture turn and restart; real provider acceptance separate |
| R040f | Selected-file bounds, descriptor-relative path/link/special-file refusal, exact text/hash/scope binding, consent/expiry/cancellation/no replay, source/import provenance, unchanged runtime grant, preserved UI and packaged fixture/restart proof |
| R040g | Same-board bounds/UUIDs, self/missing/foreign/cyclic refusal against the current graph, immutable history/legacy omission, idempotency/stale writes/event rollback, native checkboxes/dirty forms/reconnect and packaged prior-data/restart proof |
| R040h | Versioned native/host contract, prerequisite-first indices/cycles/source scope, downgrade/legacy handling, ordered/idempotent imports with retained user edits, rollback and citation provenance, escaped/session-guarded UI, packaged fixture and restart |
| R040i | Exact preview/revision consent, private Markdown/hash safety, stale task/prerequisite refusal, atomic acceptance/ToDo/history/event rollback, cancellation/interruption without replay, session-guarded downloads, preserved forms, packaged prior-data and restart |
| R040j | Exact check preview/confirmation, closed bounds/literal argv, immutable scoped revisions, idempotency/stale writes/event rollback, recovered/expired forms, keyboard/dirty-state UI and fresh/prior-schema/restart package proof |
| R050 | Structured decisions, stale/foreign proposal refusal, review return, exact-head/criteria/check binding, local integration |
| R050a | Read-only scoped preview, current acceptance/artifact/prerequisite validation, assigned-team/catalog drift, dated Git observations, exact checks, no effects, stale/expiry/refresh and authenticated packaged UI |
| R050b | Fresh scoped HEAD consent, unchanged source/index, detached locked ownership, unsafe tree/filter/path bounds, cancellation/expiry/no replay, receipt binding, session/recovered form guards, packaged real Git and restart |
| R050c | Preparation/scope binding, ownership/linked metadata refusal, raw byte/mode/index checks including hidden flags, unchanged files/index/marker, extra-file canaries, expired/cancelled claims without replay, session controls, packaged real Git/restart |
| R060 | Launch/integration crash windows, restart, cleanup/PID reuse, budgets, provider failure, sleep-gap accounting |
| R070 | Concurrent task/port claims, fairness, prerequisite bases, stale reviews, conflicting integration and recovery |
| R080 | LiveView reconnect, keyboard/focus/input preservation, narrow viewport, logs pagination/tail, timed setup |
| R090 | Full conformance + real evidence for each named provider and mixed-runtime team |
| R100 | Signed clean-machine install/update, DB backup/restore, physical sleep and complete story on actual bundle |

For Elixir changes, establish/run formatter, compiler with warnings as errors,
focused ExUnit checks and relevant Credo/Sobelow/dependency analysis. For Rust
shell changes, formatter, Clippy with warnings denied and focused tests.
Broaden only when dependencies or changed behavior justify it. Package/resource/
adapter changes also need their domain gates. Do not invent passing commands for
scripts that are absent; Development owns the exact runnable quality commands.

## Complete user-story exercise

- [ ] Start a freshly installed app from the macOS top bar into the browser.
- [ ] Authorize one supported runtime; fetch models; restart and reuse connection
  and catalog. Repeat provider acceptance for every advertised adapter.
- [ ] Save Speculator, Implementor, Secutor and Summa Rudis; add a named role with
  its own agent/model and explicit grant.
- [ ] Add empty and existing-document folders; each opens its default board and
  saved team without separate board setup. Reopening creates no duplicate board.
- [ ] Create tasks from `docs/` and eligible folder files without a manual path
  list or individual imports; inspect sources/criteria, edit, then reanalyze without
  overwriting those edits. Empty folders accept a brief. No Git prerequisite.
- [ ] Start from the same Arena; decline contextual Git initialization and prove
  no mutation or lost planning, then consent to the exact necessary baseline.
- [ ] Separately exercise Advanced custom columns/roles without making them part
  of the normal first-project path. They cannot bypass independent review.
- [ ] Start once; observe Summa Rudis dispatch and Secutor return comments;
  Speculator revises and Implementor repairs without routine approval prompts.
- [ ] Run two independent workers simultaneously and a dependent task afterward;
  force an overlapping change and validate the combined result before completion.
- [ ] Open global/Arena Tabula Gladiatorum; identify agent/model/task/progress;
  inspect scrollable logs and the redacted log file.
- [ ] Pause/resume/stop/retry, reconnect browser, restart app and sleep/wake; retain
  state/evidence with no duplicate launches or lost edits.
- [ ] Finish on a local reviewable branch with all criteria and required checks
  passed on the final candidate; prove no remote publication occurred.

Time first launch to ready-to-start. State runtime/account prerequisites and
record full installation time separately. At least one unfamiliar user must
perform the journey; a developer clicking a fixture is not ten-minute acceptance.

## Adversarial and failure cases

- Malicious docs/model output asks for home-directory reads, shell commands, new
  tools, forged reviews or DB writes: no new authority or unsafe mutation.
- Secret canaries, split chunks, nested errors and raw protocol frames never
  leak to DB, UI, files or export.
- Unauthorized browser, reused handoff token, hostile origin and expired session
  are refused. Artifact IDs cannot expose another Arena or arbitrary file.
- Expired task leases, duplicate clicks, concurrent coordinator results and
  reused PID values do not create duplicate work or kill foreign processes.
- Protected configuration changes, symlink escape, dirty original checkout and
  moved Git refs fail closed while preserving data.
- Lost protocol owner, timeout, provider revocation, missing model and exhausted
  limits produce explicit recoverable/attention states; no silent model switch.
- Secutor rejection, missing check receipt or changed candidate cannot be turned
  into Completed by Summa Rudis, a custom column or a manual drag.
- Sleep and forced process death are tested independently. Unknown external
  effect outcomes require reconciliation rather than automatic repetition.
- Prior DB copies survive failed migration; integrity/foreign keys and restored
  hashes are checked. No test reads/modifies a live user's database.

## Source development (R011)

`rtk proxy python3 test/dev_server_test.py` checks real nonblocking lock contention
in a temporary checkout, the actionable message, preserved data/lock identity and
reuse after the owner releases it. It starts no Phoenix/native/provider process.

After `rtk proxy bin/dev.build`, stop any source developer server and run:

```sh
rtk proxy bin/dev.server --smoke --port 0
```

This exercises real bootstrap, session handoff/replay rejection, HEEx/reload
injection, strict application CSP, same-origin reload-frame CSP and foreign
Host/origin/cross-site refusal. Removed Tidewave routes must return 404 and pages
must contain no toolbar or Tidewave assets. It uses only `.ccoding/ui-dev/`, runs
no provider and gracefully shuts down, retaining data. The foundation ExUnit test
checks absent development dependencies/routes/CSP exceptions in test. Browser
rendering remains separate from HTTP/header checks.

## Automatic card evidence (R040m)

R040m's focused planning checks cover whole-graph completion/event rollback,
expired and duplicate results, pre-upgrade consent, legacy partial imports,
reanalysis preserving edits, and live cards without per-suggestion buttons.
Packaged fixture restart retains exact task/revision/command hashes and reconciles
an expired running request without provider replay. See the
[R040m evidence](../worklog/2026-10-13-R040m-automatic-task-cards.md).
Fixture responses establish persistence/UI behavior, not real provider acceptance.

## Documentation-only gate

Check local links/anchors and referenced files, coherent names/flow, honest status,
unimplemented checklist items, skill references and absence of stale operational
commands. Run `rtk git diff --check`. No application tests are needed for prose
edits; record unavailable implementation checks rather than call them passing.

## Evidence record

Each task worklog records acceptance, source/build identity, exact commands and
results, fixture versus real-provider evidence, screenshots when UI changes,
skipped checks and the next action. Distinguish working tree, commit, remote
publication, native build and actually running artifact. A build does not prove
provider acceptance; passing unit tests do not prove sleep/cleanup on macOS.

R020i focused checks cover named profile/catalog/selection isolation, independent
mixed-role pickers, foreign catalog receipts, stale forms, Cursor login URL scope,
per-connection planning, unsupported Cursor planning, cancellation and expired setup
claims. Native Cursor fixtures cover file-only credentials, environment canaries,
bounded complete model parsing, redaction, signout verification and group cleanup.
Migration acceptance uses an integrity-checked SQLite backup of the eight-version
DB, runs the ninth Ecto migration on a copy and compares every previous table.
Real Cursor login completion/catalog tests require the user to finish authorization;
fixture Grok models are not evidence of account availability.

R020l catalog regression covers 256/512 Cursor entries through native parsing and
Elixir normalization, rejects overflow/late duplicates/incomplete lists, and saves
all 512 fixture choices through LiveView into Team. Actual packaged inspection
retained 256 entries (including 22 Grok variants) across app restart; see the
[R020l worklog](../worklog/2026-10-10-R020l-cursor-catalog.md). This verifies model
metadata discovery, not inference entitlement or repository execution.


R020p native protocol fixtures cover Cursor alias/default-label resolution,
parameter drift, explicit-selection and permission requirements, foreign frames,
native tool refusal, protected paths, read-only edits, output limits, cancellation,
timeout, retained effects and owned group cleanup. Mixed-team executor tests retain
Cursor Implementor/Summa Rudis and Codex Speculator/Secutor through correction and
final completion. These fixtures do not prove real-account inference.
`real_cursor_preflight` is an ignored no-prompt metadata check;
`real_cursor_task` requires explicit `one-fixture-session` usage consent and an
app-owned profile. Select exactly one synthetic read, write or denial canary.
The five-minute fixture writes its public receipt under that app's probes directory.
