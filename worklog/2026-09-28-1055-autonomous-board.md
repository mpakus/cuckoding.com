# 1055 — Autonomous board orchestration

## Start and acceptance

Claimed task 1055 on `feature/1055-autonomous-board` from clean local main
`1abbd45` (ahead of origin/main by 11). The approved plan is implementation scope:
opt-in goal planning/review/import, immutable adaptive plan revisions, bounded
role continuity/recovery, independent-task continuation, durable controls and
accessible dashboard/accounting. Fixed batches and historical grants stay intact.
All task acceptance boxes remain unchecked until supported by recorded evidence.

Required product, architecture, DB, flow, security and execution-environment
documents were read before implementation. Ponytail 4.10.0 (MIT), repository
Ponytail/workflow/architecture/LiveView/agent-adapter/local-runner/security/
observability/quality-gates guidance applies. No new framework or dependency.

## Reference investigation

- Superset's orchestration, skills and MCP documentation was read during planning.
  Adapt the bounded delegation/public handoff idea, not its terminal-scraping,
  global skill installation or cloud API. No Superset source is copied.
- `rtk xerj search --prefix ref-hydra-v1 -k 3 'session resume workspace agent'`
  and `rtk xerj search --prefix cuckoding-project-v7 -k 3 'board controller'`
  both reported the loopback XERJ node unavailable (exit 2). Used source search
  and direct pinned-peer inspection instead; no index/node was changed.
- Hydra revision `d8ad56112c2c3acfb2f65f53b6890f30a25c693c`, MIT license verified
  in LICENSE; `electron/agents/AgentManager.ts:300` restores provider/session/
  workspace identity as idle with no PID. Adapt that separation of conversation
  identity from live process ownership. Cuckoding keeps SQLite authoritative,
  verifies grants and process identities and never assumes a stored ID proves
  a live resumable process. No peer source was copied.

## Implementation and boundary review

- Added explicit opt-in authorization and finite ceilings to the existing board
  aggregate, with an additive forward migration. Fixed batches default unchanged.
- Hidden controller stages use the saved Speculator or independent Reviewer.
  Closed plans and review records are validated against original criterion IDs,
  current revision, card baseline and dependency graph before atomic import.
- Reviewed splits retain superseded membership and replacement links, and cancel
  the old unstarted card through its audited transition so later admission cannot
  accidentally duplicate it. Only unstarted pending/blocker-deferred work changes.
- Separate project/execution/task/role conversations retain attempt accounting.
  Native loading requires compatible account/model/grant/workspace/runtime and
  negotiated support; other turns use bounded public evidence. No new transport.
- Host-observed timeouts alone qualify for automatic transient retries. Cleanup
  and Git ownership checks precede retry; dirty evidence is retained on the failed
  branch and excluded from the next base. Controller time/token/cost usage and
  delivery role budgets accumulate across turns/runs. Unknown/global failures
  halt admission, while local blockers defer descendants and allow independent work.
- Questions/answers and planning controls reuse command revisions and events.
  Refresh during autonomous planning stops owned work before requiring a new
  reviewed revision; Skip cannot bypass initial plan review. Stop can supersede
  a pending control whose cleanup requires attention.
- Dashboard and modal reuse LiveView, existing dialogs and motion. Added goal
  progress, plan/review history, attention/recovery controls, answers and role
  lineage. Statistics include every session and count superseded work separately;
  review returns derive from recorded blocking findings/rejected plans.
- Reviewed external inputs (browser/model/repository) through domain validation,
  command transactions, shared admission and process controls. No filesystem,
  account, networking, policy, release or knowledge-publication grant is expanded.
  Native history replay remains excluded from work dispatch and usage.

## Verification

- `rtk env -u CR_PAT mix test test/cuckoding/board_control_test.exs
  test/cuckoding/shared_authorization_migration_test.exs
  test/cuckoding/adapters/acp/client_test.exs`: focused run passed **60 tests**;
  later board-only runs passed **30 tests** after budget, cleanup and answer checks.
- `rtk env -u CR_PAT mix quality`: an intermediate full run passed **429 tests
  and 10 properties**, Credo, Sobelow and the dependency advisory audit. Final
  post-review run passed **431 tests and 10 properties**, formatter, unused-dependency
  check, warnings-as-errors compilation, Credo, Sobelow and advisory audit (exit 0).
- `rtk node --test test/task_board_motion_test.cjs`: passed (one test).
- `rtk git diff --check`: passed. A Python link-target check passed **75 local
  documentation links across 12 changed Markdown files**. Source claims and the
  ADR/controller schemas were checked against the implementation.
- Initial failures are not passing evidence: two fixture assertions were corrected
  (mode selection before goal fields exist; persistence of the retry target),
  static-analysis complexity was reduced, and the formatter required a second
  pass for two multiline clauses. The full suite's deliberate plugin-crash logs
  are expected fixture output.

## Rendered fixture evidence and cleanup

Commands:

```sh
rtk env -u CR_PAT mix run --no-start /tmp/cuckoding-1055-preview.exs
rtk node /tmp/cuckoding-1055-browser.cjs
rtk node /tmp/cuckoding-1055-mobile.cjs
```

Only `/tmp/cuckoding-1055-preview/preview.db`, its Git repository/workspaces,
loopback port **4128** and deterministic agents were used. Power/resource/plugin
background services and project admission were disabled. The first attempted
fixture port (4098) was occupied by another application; startup failed without
signalling that application, and the fixture moved to the verified free port.

The rendered pass checked 1440×1100 and 390×844 layouts, goal/limits/consent,
keyboard Escape with focus return and Enter controls, retained modal text,
independent plan review/import, live filter focus/text/disclosure preservation,
Pause/Resume, Stop confirmation, reduced motion, reconnect/reload and home summary.
No browser page errors or horizontal document overflow. Inspected desktop goal
and mobile goal/plan viewport images under `/tmp/cuckoding-1055-preview/`.
Chrome's full-page mobile screenshot repeated compositor content; the DOM had one
panel and viewport screenshots were separately captured and visually checked.
This temporary harness is supplemental to committed domain/LiveView/motion tests.
The rendered pass preceded the final backend budget/provenance/baseline guards;
the final full suite covers those guards. No UI source changed afterward.

Verified the fixture listener with `rtk lsof -nP -iTCP:4128 -sTCP:LISTEN`, its
executable/start identity with `rtk ps -p 20022 -o pid=,comm=,lstart=`, and cwd
with `rtk lsof -a -p 20022 -d cwd -Fn`. `rtk kill -TERM 20022` gracefully ended
that owned fixture (exit 0); the listener check returned no rows. That PID is
historical evidence, not a reusable stop instruction.

The staged whitespace check exposed an extra final blank line in this newly added
worklog (the earlier unstaged check did not include new files). RTK filtered out
the diagnostic, so `rtk proxy git show --check --oneline HEAD` was used for exact
unfiltered verification. Removed the blank line and repeated the check successfully.
This read-only diagnostic was the task's sole RTK proxy exception.

## Delivery boundaries

This is source/fixture implementation evidence on `feature/1055-autonomous-board`.
The installed application and user database were not rebuilt, migrated or restarted.
No local-main merge, remote publication or Pages deployment is claimed.

- [ ] Real-provider autonomous planning/replanning and native conversation continuation.
- [ ] Packaged developer-app build/run of task 1055.
- [ ] Physical sleep/wake and clean-machine signed release acceptance.

Earlier task-1054 provider/app evidence is historical and does not close these gates.
