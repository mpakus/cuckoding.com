# 1050 — README and documentation synchronization

Acceptance: inspect README/docs against current source; update operating paths,
roles, board control and acceptance status; preserve historical evidence and all
existing implementation changes; validate links/anchors/claims and whitespace.

Claim task 1050 only. This is the documentation follow-up to task 1049 on the
existing feature/1049-board-controller working tree. Its uncommitted source,
migration, tests and documentation are expected prior work, not conflicting user
edits. No branch integration, commit, publication, rebuild or restart is requested.

Applied repository Ponytail minimalism and quality-gates; upstream Ponytail
4.10.0, full mode, MIT. Documentation-only scope uses source/link/structure checks
instead of rerunning product suites or creating runtime evidence. Every shell
command is RTK-prefixed.

## Findings and changes

- README now explains saved agents and the three execution paths: sequential
  Draft/Ready board batches with reviewed commit handoff, concurrent Ready-task
  project admission, and individual preparation/start on unclaimed boards.
  Product, Flow, Configuration and release/operator guidance use the same terms.
- Documented frozen batch roles/policy, live authorization checks, queued-binding
  exclusions, the decision cap and confirmed pending-request refresh. The DB
  diagram includes batch membership/run links and optional prepared environments;
  timestamp/revision language matches the current Ecto schemas.
- Corrected recovery and accounting overclaims: delivery budget exhaustion blocks
  work; periodic provider checkpoints are not guaranteed by example YAML; Quit
  uses the guarded hibernation path; generic metrics exports remain planned.
  Whole-batch accounting queries all linked records but cannot reconstruct pruned
  resource samples, predict remaining spend or invent missing measurements.
- Marked Phase 0 entry evidence, walking-skeleton provider checks and earlier
  packaging observations as historical. PLAN, DECISIONS, the documentation audit
  and release readiness link task 1049's recorded source/browser evidence while
  leaving real-provider, physical sleep/wake, packaged-app and release gates open.

Source claims were traced through `BoardControl.preflight/2`, `decision_input/1`,
control validation, snapshot and role checks; `Decision.validate/3`;
`Statistics.snapshot/1`; `RunControl.admit/3`; scheduler/manual/project launch
callers; Git evidence/ancestry checks; `AgentBindings.connect_run/3`; current schemas,
migration and LiveView components. Bootstrap/toolchain statements were compared
with `.tool-versions`, `mix.exs`, `mix.lock`, configuration and build entrypoints.
Power, budget and export wording was checked against the shell shutdown policy,
delivery executor, metrics retention and diagnostics export code. No external
provider/version claim was refreshed from the web.

## Verification

| Exact command / inspection | Result |
| --- | --- |
| `rtk python3 /tmp/cuckoding-1050-doc-check.py` | Passed: 46 Markdown files, 178 local links/anchors and balanced code fences; 0 errors. External links were excluded. |
| Same check against `/tmp/cuckoding-1050-source-hashes.json` | All 276 baseline implementation files under `lib/`, `test/`, `config/`, migrations, plus `mix.exs`/`mix.lock`, retained their SHA-256 hashes. |
| `rtk git diff --check` | Passed, including task/worklog files made visible with intent-to-add. |
| `rtk git diff -- README.md docs/CONFIGURATION.md docs/LONG_RUNNING_AND_POWER.md docs/IMPLEMENTATION_READINESS.md docs/RELEASE_READINESS.md` and focused `rtk rg` / `rtk sed` source reads | Reviewed source claims, current/historical labels, controls, task dependencies and checklist coverage. |

The link/hash script and baseline manifest are temporary documentation-audit
artifacts, not new product tooling. No application tests were rerun: task 1049's
369 tests, 10 properties, migration, motion and rendered-browser results are
explicitly attributed to its worklog, not claimed as task 1050 evidence.

This task changes documentation and its task/worklog only. Existing implementation
edits remain intact on `feature/1049-board-controller`, based on `55f1bd1`.
Nothing was committed, integrated into main, published, built, installed,
migrated or restarted by this documentation pass.
