# 1031 — Board agents without per-run selection

Claimed 2026-09-22 on clean `main`; branch
`feature/1031-board-agent-auto-run`. Acceptance criteria are in the task file.

The linked queued run reproduced the problem: its immutable role snapshot has
connection keys and executable settings but no saved-agent IDs, while project
configuration revision 7 has the intended Speculator and Implementator IDs.
The board is still on those legacy role rows, so the run asks for three manual
bindings. Project automatic work is paused; the existing dispatcher already
runs eligible Ready tasks after Project Start.

Read the required product, architecture, database, flow, security, execution,
autonomous-flow, reference-coding, task, and relevant authorization/UI docs.
Upstream Ponytail 4.10.0 is MIT licensed and active in full mode. This change
reuses `ProjectWorkflow.apply_project_roles/2`, `AgentBindings`, run events, and
`ProjectAutopilot`; no unfamiliar external pattern or new boundary is needed.

Restated acceptance before implementation:

- one explicit board-level role application supplies saved-agent identity to
  future runs and compatible queued work;
- queued binding remains append-only and audited instead of rewriting the run
  snapshot, while running/completed history is untouched;
- missing assignment recovery points to board/project configuration, not a
  repeated per-run picker;
- automatic admission remains limited to Ready tasks and preserves provider
  authorization, human completion, and release gates.

Implementation:

- Consolidated the legacy board upgrade into `apply_project_roles/2`. One
  explicit board assignment updates future role rows and appends
  `run.agent_connected` events for every compatible queued role.
- Prevalidates every missing role before writing any bindings to a queued run.
  An incompatible queued run receives no new bindings; running/completed runs
  are not queried. Workflow snapshots remain byte-for-byte unchanged.
- Real provider roles now require a compatible saved-agent ID before a new
  delivery or planning run can be prepared. The fake adapter remains available
  for deterministic tests without fabricating provider identity.
- Removed the per-run agent picker and its duplicate account catalog read. A
  legacy unbound run points to **Assign agents to board**; grouped connected
  agents still expose their one reusable authorization action.
- Renamed the existing project-settings action to **Assign agents to board**
  and synchronized product, architecture, database, flow, authorization,
  configuration, dashboard, and autonomous-flow documentation.

Security review:

- Only provider account IDs enter board settings and append-only run events;
  no credential value, provider output, personal CLI home, or new capability is
  read or persisted. Start still performs the live authorization probe.
- Automatic project admission remains limited to Ready tasks and preserves
  capability, human local-completion, release, and policy-approval gates. The
  host runner remains explicitly not a sandbox.
- The queued-run compatibility check uses runtime plus executable/helper
  settings and never display names. A mismatch cannot partially bind a run.

Verification:

- `rtk mix compile --warnings-as-errors` — passed.
- `rtk mix test test/cuckoding/project_workflow_test.exs test/cuckoding_web/project_edit_live_test.exs test/cuckoding_web/board_live_test.exs` — 28 tests, 0 failures.
- `rtk mix quality` — 10 properties and 301 tests passed; Credo strict found no
  issues; Sobelow and Hex audit passed. The two fixture worker crashes in the
  log are intentional supervisor tests.
- `rtk mix assets.build` — Tailwind and esbuild passed.
- `rtk git diff --check` — passed.
- Created online backup `tmp/cuckoding_dev_before_20260922_1031.db`; source
  database integrity and foreign-key checks passed before the live assignment.
- Applied project configuration revision 7 to Echo/Product. The audited board
  event reports three compatible queued runs connected. The linked Run 2 now
  renders Implementator once for Coding and Speculator once for Specifications
  plus Review, with no role selectors. Its immutable snapshot remains queued.
- Post-change SQLite integrity passed; the project remained paused with zero
  running runs and zero running processes. No provider workflow was started.

The live domain call started the supervised application, so normal startup
reconciliation also appended `continue` facts for its recoverable queued/blocked
runs. It did not start providers or processes. All repository shell commands
used RTK; no `rtk proxy` exception was needed.
