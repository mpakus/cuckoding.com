# Worklog — 1032 Home operations dashboard

## Metadata

- Date/time (UTC): 2026-09-23
- Task: 1032
- Status: done
- Human/agent owner: codex
- Branch: feature/1033-project-state-agent-chart (to be fast-forwarded to main)
- Start revision: 5d2d532
- End revision: 6d2bd1f (dashboard feature commit fast-forwarded to main)

## Intended outcome

Projects first; live activity charts and agent snapshot; filterable Operations table; Application and Resources dashboards.

## Context inspected

- Clean `main` at task start.
- Existing `StatusLive`, `AgentFloor`, activity/usage components, dashboard specification, and live home page.
- Reused the committed-event subscription and five-second database refresh; no chart dependency needed for small bounded bar charts.

## Work performed

- Reordered the home page in DOM and visual order: Projects, Recent activity, Operations, Application and resources.
- Added a latest-20-event activity-mix chart using native meters and a matching accessible count table, category buttons, and a collapsible committed-event log. Current agent sessions show project, task, role, runtime, model, state, elapsed wall age, and an Inspect link.
- Replaced operation cards with a latest-50-run table and local state, project, and search filters. Kept queued runs and safe run/task links; no lifecycle command is issued by filtering.
- Added application dependency health and measured resource tiles. Kept missing samples distinct from zero usage. Recomputed activity freshness during periodic refresh.
- Updated `docs/UI_DASHBOARD.md` and added focused LiveView tests for section order, committed-event arrival, chart filtering, and operation filtering.
- No chart library was added: native meters render under the app's no-inline-style content security policy. Reference-coding peer retrieval was unnecessary for this existing LiveView/read-model rearrangement.

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| `rtk mix test test/cuckoding_web/status_live_test.exs test/cuckoding_web/agent_floor_live_test.exs` | pass | 14 tests, 0 failures before the final live-event test addition. |
| `rtk mix test test/cuckoding_web/status_live_test.exs` | pass | 5 tests, 0 failures after the live-event addition. |
| `rtk mix format --check-formatted` | pass | No formatting changes required. |
| `rtk mix quality` | pass | 10 properties, 304 tests, 0 failures; Credo 0 issues; Sobelow clean; Hex audit no advisories. The plugin supervisor tests intentionally log fixture crashes. |
| `rtk mix assets.build` | pass | Tailwind and esbuild completed; no tracked asset changes. |
| Browser at 792px and 375px | pass | Requested section order, chart values 11/9/0 of 20, live category filter, Operations filter 9 of 14, and safe links visible; 375px document width equaled viewport width. Narrow table scrolls within its labeled region. |

## Telemetry and operational evidence

- Home refresh: existing committed-event PubSub hint plus five-second durable reload; no new polling worker.
- Chart scope: latest 20 committed public events, not a historical rate. Operations scope: latest 50 runs. Resource values are latest measured active-session samples; host limits remain advisory.

## Decisions and deviations

- Kept existing Phoenix LiveView and read models; native meters replaced an attempted inline-width bar after browser inspection showed CSP blocked inline styles.
- Operations actions are links to Run and Task details, not state-changing shortcuts; this preserves existing authorization and confirmation paths.

## Risks and blockers

- The browser console still reports a `MutationObserver.observe` type error on reload. No `MutationObserver` call exists in application source; the error was also present before final changes, so its owner remains unconfirmed. Page interactions and LiveView tests passed.
- No physical screen-reader session or 200% zoom run was performed. Native controls, labels, focus classes, semantic table, and count alternative were inspected.

## Handoff

- User can inspect the open local home page at `http://127.0.0.1:4000/`; no provider run, Git push, or release action was triggered.

## Checklist

- [x] Task acceptance criteria reviewed and completed.
- [x] Dashboard documentation updated.
- [x] Tests, build, static checks, and browser evidence recorded.
- [x] Secrets and sensitive content excluded from the change.
- [x] Residual browser-console and accessibility verification limits explicit.
