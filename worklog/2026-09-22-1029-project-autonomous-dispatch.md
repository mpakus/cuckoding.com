# 1029 — Project-level autonomous task dispatch

Claimed 2026-09-22 on clean `main` at `bb4ad38`; branch
`feature/1029-project-autonomous-dispatch`. Acceptance criteria are in the task
file. No user changes were present at claim.

Read the required product, architecture, database, flow, security, execution,
and task documents. Upstream Ponytail 4.10.0 is MIT licensed and active in full
mode. The XERJ node at loopback:9200 was unavailable, so source was inspected
directly. Pinned MIT Agetor `eb74ab5` at `src/bun/terminals.ts:125-139`
reserves an in-flight slot before asynchronous setup; the idea, not code, is
relevant to Cuckoding's capacity race. Cuckoding must instead use durable
SQLite claims and preserve its existing policy/auth/run boundaries.

Implementation:

- Added forward-only `project_autopilots` projection and project event stream
  transitions. The supervised worker is a disposable admission loop; test
  configuration disables only its background timer so DB sandbox tests remain
  deterministic. An explicit Start still wakes it.
- A board may have unassigned role slots. Applying current saved project roles
  validates account compatibility and updates board assignments for future
  runs, without changing existing run snapshots.
- The worker reuses `Scheduler.plan/1`, `ProjectWorkflow.prepare_task/1`, and
  `GuidedRun.start/1`. A task cannot create a second active run inside the
  SQLite transaction. Automatic Ready admission and queued starts observe
  board, project, trusted-policy, and global limits. The trusted policy remains
  an upper bound on the user-selected project cap. Archiving stops admission.
- Project, board, and dashboard LiveViews show operation state and recovery
  reasons. Pause stops new admission; active runs are not killed. Human task
  proposal selection, local completion, release, and changed-policy approval
  remain explicit.

Security review: No credential values or personal CLI homes were added; saved
accounts remain references resolved by the existing adapter boundary. Start
does not grant new network/filesystem/plugin capabilities. All generated run
paths and branches still pass the existing preparation boundary. Events store
bounded state/issue codes, not prompts or provider output. The host runner is
still not a sandbox. The `rtk proxy` inspection calls were only for exact,
unfiltered file excerpts; all repository commands otherwise used RTK.

Verification (local):

- `rtk mix test test/cuckoding/project_workflow_test.exs` — 14 tests, 0 failures:
  board-first setup, role application, durable limits, one-slot admission,
  pause/resume, worker restart projection, distinct blocked-task threshold,
  archived-project gate.
- `rtk mix test test/cuckoding/execution/scheduler_test.exs` — passing as part
  of the focused run; added regression proving a UI project override cannot
  raise the trusted policy cap.
- `rtk mix test test/cuckoding/shared_authorization_migration_test.exs` —
  prior-schema copy upgrades through the new migration with preserved account
  data, foreign-key integrity, and SQLite integrity checks.
- `rtk mix assets.build` — passed (Tailwind and esbuild).
- `rtk mix quality` — format, unused-dependency check, warning-free compile,
  10 properties and 298 tests, Credo strict, Sobelow, and Hex audit passed.
  The two fixture worker crashes
  printed during the suite are intentional supervisor recovery tests.
- `rtk git diff --check` — passed before final worklog edits.

Remaining acceptance, not claimed passing: real authorized Codex/Cursor/Claude
concurrency on a signed clean macOS build; sleep/wake and long-run provider
refresh; direct observation of production process/port pressure. Local tests
exercise the durable dispatch boundary, not external provider uptime.
