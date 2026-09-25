# 1047 — Compact task message history

Acceptance: shared LiveView activity UI, latest 30, automatic/accessibly controlled
history, bounded mounted entries, preserved drafts/history, multi-run cursors,
redaction, compact readable entries, tests/docs/native delivery.

Started from clean main 1271d17 on feature/1047-task-message-history. Continuing
Ponytail 4.10.0 full (MIT), LiveView, observability and quality-gates guidance
already read in this conversation. Reuse ActivityComponents and LiveView's
native viewport events/streams; no new scrolling framework. Source references:
RunLive paging/refresh and LiveView 1.2.12 hooks.ts edge detection. TaskLive's
old growing list starts at 100 and grows to 5,000; replace it with exclusive
server-owned run/event sequence cursors. `rtk proxy` exceptions are exact source,
protocol and SQLite reads plus build/test diagnostics.

Moved the existing run pagination into ActivityHistoryComponent and reused it
from TaskLive. ActivityComponents owns the shared HEEx panel; TaskLive no longer
queries or accumulates thousands of message rows. Task paging stays in the
existing ActivityStream read model, uses run/event sequence pairs (including
timestamp ties), and keeps the previous message categories and redaction.
Long task messages collapse with native details/summary; complete text remains
available. No extra browser scroll framework. Parent refresh revision signals
update latest activity without resetting a history reader's window or task draft.

`rtk env -u CR_PAT mix format` and
`rtk env -u CR_PAT mix test test/cuckoding_web/agent_floor_live_test.exs test/cuckoding/project_workflow_test.exs test/cuckoding_web/board_live_test.exs`:
41 tests, 0 failures. Added 200-message/two-run history with equal timestamps,
exclusive server cursors, another task exclusion, newer/older paging, 90-entry
bound, live update preservation, unsaved draft preservation, native disclosure
and reconnect checks. Existing run regressions now assert rendered entries
rather than private parent LiveView state. During implementation the compiler
caught the repository's missing live_component helper; used Phoenix.LiveComponent
directly. LiveView then required a static root tag; added the standard wrapper.
No changes to permissions, commands, persisted workflow state or event content.

`rtk env -u CR_PAT mix quality`: formatter, unused-dependency check,
warnings-as-errors compiler, full suite passed (10 properties, 352 tests,
0 failures). Credo requested splitting the composite-cursor query; extracted
only the two direction predicates. Subsequent focused task/run tests (30 tests),
`mix credo --strict`, `mix sobelow --config`, and `mix hex.audit`, all via
`rtk env -u CR_PAT`, passed with no findings/advisories. Also reset streams when
the shared component's task/run scope changes, with a regression preventing
entries from the prior scope remaining visible. Native UI interaction was
interrupted by active Chrome use; final visual verification remains pending.

Native rollout: task implementation merged locally to main as a731e27.
`rtk env -u CR_PAT ./bin/dev.build` passed the production asset/compiler/release
gates, Ruby metadata (6/15) and restart (6/98) checks, promotion checks, Rust
fmt/10 tests/clippy, native bundle and sterile authentication, shutdown,
safe-mode, update/rollback checks. Read-only native inventory before restart:
one Blocked run, one Done run, all six processes Exited; the requested task
contains 36 timeline messages. `rtk ./bin/dev.restart` gracefully stopped owned
PID 41644, verified cleanup, and launched the new bundle at
http://127.0.0.1:64521. The existing DBngin PATH warning did not prevent restart.
No migration, task-content edit, provider run, remote push or signed release.

`rtk git diff --check` passed. Automated component/domain verification and
native rollout are complete. Remaining handoff: open the native menu's normal
authenticated dashboard and visually check compact rows, native disclosures
and scrolling on the supplied task; no browser-authentication bypass was used.
