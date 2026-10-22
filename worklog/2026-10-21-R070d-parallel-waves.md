# R070d — Independent task waves

Claimed from local main `4feb52a` on `feature/r070d-parallel-waves`.
Ponytail full, workflow, architecture, LiveView, local-runner, security, quality
and incremental/TDD guidance apply. All shell commands use RTK; proxy preserves
exact verification/source output. `Untitled.md.age` remains unread/untouched.

The native combination and attempt-receipt prerequisites are merged. This slice
adds actual task-lane authority and dispatch. Proposed waves allow two independent
tasks to prepare/implement while the reviewed head stays fixed, then serialize
review/integration. Shared exact connections still permit one turn, so overlap
depends on assigned bindings. No credential cloning or same-profile concurrency
is inferred. Combined candidates need new independent evidence.

Repository queue: the new-only native I/O boundary uses a local OTP process-owned
lock by pinned device/inode, a 65-second queue ceiling and the stage's existing
active/deadline callback. The supervised worker waits, never the coordinator.
Cancellation before acquisition runs no helper; owner death releases only the VM
queue, never native effect/cleanup authority. Native repository locks remain.
Two queue tests were red before the module, then green: same-repository ordering,
independent repository progress, queued cancellation and killed-owner release.
The new policy is not enabled in Start yet; workflow/control implementation follows.

## Implementation and regression work

- New Starts freeze `parallelism: parallel-waves-v1`. Task contexts own stages;
  SQLite reserves independent ready tasks before supervised dispatch. Two global
  workers and one provider turn per exact connection remain. Native I/O queues
  never confer ownership/cleanup. Additional same-role execution slots remain open.
- A wave captures implementations before serial checks/Secutor/CAS. Changed heads
  use R070b and clear prior check/review authority. Recorded verified conflicts
  consume a review round and use a fresh coordinator/Speculator/writer; failed
  attempts/edits remain immutable. Exact new combined-receipt bindings are checked.
- Pause/Stop cover every stage. Timing fences bind every active claim; the original
  cancellation timestamp prevents sibling receipts renewing the five-second lease
  window. Late siblings retain rejected evidence without changing result context.
- Failed lanes drain before attention. Each failure retains its own explicit
  Retry/Skip; multiple failures never become one automatic retry. Ordinary settled
  transient failures schedule existing backoff after a clean drain; user Pause
  keeps continuation explicit. Restart retains every interrupted claim and queues
  exact provider-closure reads individually, for Stop/capacity release only.
- The fifteenth migration changes claim indexes only. Separate 11/14-schema
  fixtures verify backups/integrity/FKs; fourteen-schema records include an exact
  synthetic running claim and its related authorities. No real workspace migrated.
- New wave lifecycle/selection lives in `Battles.Waves`, native I/O waiting in
  `BattleRepository`; existing authority and receipt owners remain. Wave tests use
  a separate module and the shared battle factory rather than duplicate fixtures.

Initial focused cases exposed premature Stop after one worker, Pause misclassifying
a running sibling, wrong task focus during retained integration recovery, missing
whole-wave interruption, and delayed backoff selection. These were fixed before
completion. Crash testing exposed redundant admission polling inside a killable
coordinator transaction; the scheduler now filters already-exclusive jobs before
claiming, while SQLite still owns every admission decision.

The first readiness mutation survived an already-aligned topological ordering.
A new adjacent-dependent scenario closes that coverage gap: baseline passes;
removing the prerequisite test fails the claimed task IDs (exit 2). Exact source
was restored in `finally`. Multiple-worker and closure/late/retry cases are fixtures,
not real-provider or physical-sleep acceptance. Final quality/browser/build/smoke
results remain to be recorded below.

## Final verification

- `rtk proxy mix quality` with the pinned PATH: exit 0, **480 passed** in
  27.0 seconds; format, warnings-as-errors compilation, strict Credo (130 files,
  1,907 modules/functions, no issues), Sobelow and both dependency audits passed.
  Exact output retained privately at `.ccoding/r070d-quality-final.log`.
  Expected migration-module redefinition and Sobelow lockfile-parser diagnostics
  remain tool/test warnings, not compiler warnings or hidden test failures.
- Read-only review checked every changed authority path, exact combined DTO,
  capacity/claim gates, legacy policies, controls/late receipts/closure queues,
  transaction ownership and public UI projections. No additional dependency,
  provider grant, credential/profile clone or shell access was introduced.
- Local documentation reference check: **230 references**, zero missing targets;
  `rtk proxy git diff --check`: pass. A first one-line reference-check invocation
  had a Python quoting error; the corrected heredoc check above passed.
- Source browser on the separate `.ccoding/ui-dev` root: desktop and **320 × 712**
  device viewport show the single Start, bounded wave summary and readable
  Inspect scope without text clipping; the disclosure opens by Space while
  focused. Existing missing-role blockers correctly prevent usage. No inference
  or current saved-team adoption was attempted. This is not a full accessibility,
  real-account or timed unfamiliar-user test.
- Before source schema 14 → 15, verified the private canonical root, unchanged
  free shell lock, zero active work, SQLite integrity/FKs and a private backup:
  `.ccoding/r070d-ui-backup-13fda500-4d93-4d96-a6b1-753f3b90320d/foundation-before-upgrade.db`
  (SHA256 `9018e616181a6a7245e51abf1b1c16b54defe3e45c3f76cf7b2365240eb26af5`).
  After upgrade, 15 migrations, integrity/FKs clean. A post-upgrade private backup
  precedes verified normal launcher shutdown; launcher/backend exited, lock
  released and port 63773 closed. The owned browser tab was closed.
- `rtk proxy bin/dev.server --smoke --port 0`: pass, session/reload/origin/CSP and
  no Tidewave. Launcher shut down through its normal finally path.
- `rtk proxy bin/dev.build`: pass; `rtk proxy codesign --verify --deep --strict
  --verbose=2 …/Cuckoding.app`: pass. Bundled helper SHA256
  `f497790fd1e36dea85e6511b975f73685cd73d70202aad059f213d6e2ff3b657`.
- `rtk proxy bin/smoke`: pass: bundled launch/bootstrap/session/handoff replay and
  origin refusal, heartbeat, normal Quit and listener closure. Retained isolated
  data: `/private/tmp/ccoding-smoke.sWDUks`. The app is not left running.
- Rust source was unchanged from R070b's 94 passing / five opt-in ignored native
  tests plus clean format/all-target Clippy. Those checks were not repeated for
  this Elixir-only slice; packaging rebuilt the same native source successfully.

No new real-account inference, physical sleep, Developer ID/notarization,
clean-machine install, custom execution workflow or additional role slots were
proved. The full beta goal stays active. Untracked `Untitled.md.age` remains
untouched and excluded. No push or publication is authorized by this merge.
