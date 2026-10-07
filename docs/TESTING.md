# Verification and acceptance

R010 has current foundation checks; see its [worklog](../worklog/2026-10-06-R010-local-foundation.md)
and [runnable commands](DEVELOPMENT.md#quality-and-bundled-smoke). Later slice
and full-story gates remain open. Historical test counts do not establish proof.

## Gates by slice

| Slice | Smallest required evidence |
| --- | --- |
| R010 | Clean migration + prior-data isolation, event/command idempotency, shell authentication/replay/loopback, graceful Quit |
| R015 | Static links/assets/scope, motion and denied-storage behavior, desktop/narrow/keyboard inspection; [commands](SITE.md#preview-and-checks) |
| R017 | Brand export reproducibility, four three-layer scenes, alpha, crossing weapons, all-layer pause/reduced motion, desktop/narrow rendering and renamed bundle smoke |
| R020a | Executable confirmation/identity, version allowlist, bounded/split/malformed output, clean environment, timeout/cancellation/descendants, durable interruption and prior-schema upgrade |
| R020b | Bounded RPC, private profile/config, model pages/cursors/validation, stale retention/age, account separation, cancellation, prior-schema copy and real signed-out inspection |
| R020c | Consent/invalidation, official URL validation and session redirect, matching completion, profile exclusion, cancel/cleanup, uncertain restart, real login start/cancel and packaged UI |
| R020d | Usage consent, fresh identity/catalog binding, effective grant preflight, model/thread/turn matching, early completion, tool refusal, cancellation/no replay, closed receipts/canaries, reconnect UI and packaged smoke; real signed-in responses remain separate |
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
| R050 | Structured decisions, stale/foreign proposal refusal, review return, exact-head/criteria/check binding, local integration |
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
- [ ] Create empty and existing-document Arenas; decline Git init once and prove
  no mutation, then consent and inspect the baseline commit.
- [ ] Create default Tabula, add a custom column/role, generate tasks from brief
  and docs, inspect criteria and edit before starting.
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
