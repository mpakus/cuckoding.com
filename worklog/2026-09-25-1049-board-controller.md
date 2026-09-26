# 1049 — Sequential board controller

Acceptance: implement CTRL-01–07 in CUCKODING-CONTROL.md: one reviewed batch,
active Speculator controller, deterministic priority/dependencies, one delivery
task, local completion and reviewed commit chain, safe controls/recovery,
whole-batch telemetry, accessible live UI, regression and release evidence.

Preserved the preceding documentation as local commit 55f1bd1 on task 1048's
branch, then created feature/1049-board-controller. Claim only task 1049; the
seven CTRL identifiers are dependent slices of this one feature.

Ponytail 4.10.0 full (MIT); workflow, architecture, local-runner, security,
observability, LiveView and quality-gates skills applied. Required product,
architecture, DB, flow, security, execution-environment and reference docs read.

Reference coding: `rtk xerj search --prefix cuckoding-project-v7 -k 2 'scheduler task admission leases'`
failed: no node reachable on localhost:9200. Read pinned peer source directly:
vibe-kanban revision 735654971bd396aa97b65166955678e4c34f8bf8,
crates/worktree-manager/src/worktree_manager.rs:52–100. Verified LICENSE is
Apache-2.0. Reuse the idea of a centrally serialized worktree-creation boundary,
not copied code. Cuckoding additionally requires durable membership, immutable
reviewed bases, ownership markers and no automatic force-cleanup. Local reuse:
ProjectWorkflow, WalkingSkeleton stages, Commands/EventStore, RunControl,
Scheduler, GitService, AgentFloor and telemetry. No new dependency.

Migration decision: retain the checked task.kind enum and store hidden controller
tasks using the existing board_intake representation, with an explicit
BoardExecution controller_task_id and board_control stage. This avoids rebuilding
the historical tasks table while preserving distinct trusted controller purpose.

## Implementation

- Added forward-only batch/membership persistence and nullable run linkage. The
  partial unique index retains ownership through pause, attention and pending
  controls, releasing it only for terminal outcomes. Commands use stable keys
  and expected revisions; events are persisted before LiveView notification.
- Start board reviews a fixed Draft/Ready snapshot, saved roles/models/budgets,
  dependencies and exclusions, then requires automatic-local-completion consent.
  New cards wait for another batch. Confirmed Refresh binds the reviewed pending
  requests/dependencies and rejects concurrent edits; it cannot expand grants.
- The assigned Speculator runs a bounded read-only decision stage. Cuckoding
  validates closed proposals, ordering and state; shared preparation/admission
  prevents queued, manual and autopilot bypass. Launch revalidates the snapshot,
  policy, authorization and Git base even after preparation/capacity waiting.
- Reviewed delivery commits become subsequent execution bases. Original project
  provenance remains separate; default-branch drift, modified evidence and
  protected paths halt advancement. Skipped changes never enter the next base.
- Pause/Resume/Stop/Skip/Retry retain durable intent and history. Missing workers
  require explicit recovery; failed preparation without an environment can be
  retried only after verifying no agent attempt or orchestration worker exists.
  Retry retains the original request instead of silently accepting changed scope.
- Board/home panels show role progress, public decisions, controls, complete
  attempt/session accounting and evidence. Token/cost coverage and sample time
  distinguish missing/partial/historical data. Pause and sleep are separate
  potentially overlapping intervals. Existing 200 ms motion is reused.
- Updated the nine affected product/architecture/data/flow/security/execution/UI/
  autonomy/testing documents, ADR-030 and the control plan/checklists.

The existing worker's `enabled: false` option now also suppresses explicit wake
casts. Previously an ostensibly disabled test/fixture worker could start queued
work during a LiveView event. Shared admission also reserves the short interval
between a run starting and its first agent session, preventing oversubscription.

The first dependency audit found the newly published `lazy_html` security
advisory. Updated only the existing test dependency pin/lock from 0.1.12 to
0.1.13 (Apache-2.0); no dependency was added. Verified with
`rtk env -u CR_PAT mix hex.info lazy_html` and the
[upstream 0.1.13 release](https://github.com/dashbitco/lazy_html/releases/tag/v0.1.13),
which identifies the SVG/MathML escaping fix for CVE-2026-92106. Applied with
`rtk env -u CR_PAT mix deps.update lazy_html`. The final audit is clean.

## Verification

Commands run from this branch, with `CR_PAT` removed from Mix tooling's
environment. No credential values were printed or committed.

| Command | Result |
| --- | --- |
| `rtk env -u CR_PAT mix format` | Passed after each source/test refinement. |
| `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs` | Focused iterations passed; last standalone run had 16 tests. Final suite includes all 17 controller regressions, including the later external-prerequisite case. |
| `rtk env -u CR_PAT mix quality` | Final source run: **369 tests, 10 properties, 0 failures** (seed 836168). Format, unused-lock check, warnings-as-errors compilation, strict Credo, Sobelow and Hex advisory audit all passed. |
| `rtk env -u CR_PAT mix test test/cuckoding/shared_authorization_migration_test.exs` | 1 test passed after strengthening uniqueness coverage to use distinct controller tasks: running/paused retain the board claim, stopped releases it. Prior task/run data, foreign keys and integrity remain valid. |
| `rtk env -u CR_PAT mix format --check-formatted` | Passed after the final migration-test refinement. |
| `rtk env -u CR_PAT mix credo --strict` | Passed after the final migration-test refinement. |
| `rtk env -u CR_PAT mix assets.build` | Tailwind 4.2.1 and esbuild passed. |
| `rtk node --test test/task_board_motion_test.cjs` | 1 test passed: state motion, reduced motion, focus preservation, ordinary updates and cleanup. |
| `rtk node /tmp/cuckoding-1049-browser.cjs` | Isolated Chrome browser check passed; details below. |
| `rtk python3 /tmp/cuckoding-1049-doc-check.py` | Validated 13 changed Markdown files, local links/anchors, seven CTRL slices and three explicitly open external gates. |
| `rtk git diff --check` | Passed. |

The full suite intentionally emits plugin-crash fixture logs. Its contention
case also exercised bounded `BEGIN IMMEDIATE` retries; the final run still passed.
Earlier failures were resolved before the final evidence: fake worker wake
races, a missing required sequence in a new preparation fixture, an overly deep
Credo function, and the dependency advisory. They are not counted as passes.

The 17 controller regressions cover fixed mixed batches and real Git handoff,
external prerequisite code availability, deterministic priority ties/concurrent
starts, invalid/stale proposals, capacity waiting, manual launch rejection,
edits after preparation, pause/resume, skip/defer and finished-with-skips,
preserved unreviewed commits, lost-worker and failed-preparation retry, protected
path approval, finite decision budget, refresh/drift, complete accounting across
106 sessions with duplicate usage events, and the LiveView start/control flow.
A controlled real shell process verifies controller suspension, resume and
cleanup, using deterministic output; this is not a paid-provider acceptance run.
Existing full-suite workflow, runtime authorization, Git, security, accounting,
power/reconciliation and lifecycle tests also remain green.

## Rendered acceptance and fixture cleanup

Started a separate fixture with:

```sh
rtk env -u CR_PAT mix run --no-start /tmp/cuckoding-1049-preview.exs
rtk node /tmp/cuckoding-1049-browser.cjs
```

It used only `/tmp/cuckoding-1049-preview/preview.db`, a temporary Git repository
and workspaces, deterministic agents, and loopback port 4097. Background admission,
resource/power sampling and plugin discovery were disabled; explicit file-triggered
dispatch drove a committed controller transition. The installed user's app/data
were not migrated or restarted. Chrome was an isolated headless browser context.

Checks at 1440×1100 and 390×844: reviewed consent, ordered queue, keyboard Escape
and focus return, text/focus/disclosure retention across committed updates, Pause,
Skip and Refresh confirmation, reduced-motion layout, no horizontal document
overflow, reload/reconnect and home summary. No browser page errors. Rendered
screenshots inspected: `preflight-desktop.png`, `board-desktop.png`,
`refresh-desktop.png`, `board-mobile.png` and `home-mobile.png`, all under
`/tmp/cuckoding-1049-preview/`. The harness and screenshots are temporary local
evidence; repeatable domain/LiveView/motion checks remain in the repository.
The last browser pass preceded only the additional launch-time validation guard;
the final source quality run covers that guard and its queued-edit regression.

Stopped only the owned fixture listener after verifying it with
`rtk lsof -nP -iTCP:4097 -sTCP:LISTEN`; graceful `rtk kill -TERM 13886` ended the
fixture, and the listener check then returned no rows. This PID is historical
verification evidence, never an instruction to reuse it for future cleanup.

## Delivery and remaining gates

Implemented as working-tree changes on `feature/1049-board-controller`, based on
`55f1bd1378052aacd10f22c1095a5ec47db94417`. No feature commit, local-main integration,
remote publication, Pages deployment, native bundle build/install or change to
the installed running application is claimed.

- [ ] Real-provider multi-task execution, correction loops, live sign-in expiry,
  requested/observed models and provider usage evidence.
- [ ] Physical sleep/wake and packaged-app restart with live owned processes and
  provider checkpoints.
- [ ] Signed clean-machine macOS build/install and actual-running-revision checks.

Those release gates remain open in CUCKODING-CONTROL.md. No push, PR, merge,
policy expansion or global knowledge publication was performed by this feature.
