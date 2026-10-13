# R040m · Automatic task cards

Claimed from clean main `8152f0f`, synchronized with origin/main.
Acceptance: [task](../tasks/R040m-automatic-task-cards.md).

Ponytail full 5.2.0 (MIT), workflow-and-kanban, elixir-phoenix-liveview,
security-review and quality-gates apply. Reuse Planning's completion transaction
and Tabulae's draft/import receipt writer; no new worker, schema or dependency.
Model output remains untrusted data and grants no execution authority.
`rtk proxy` supplies exact source/script/build/protocol and process identity output.

Implementation:
- Reused `8152f0f` owners `lib/cuckoding/planning.ex:161` (`finish`) and
  `lib/cuckoding/tabulae.ex:225` (`persist`) / `:347` (import writer). New requests
  freeze `card_creation: automatic-v1` in the existing setup fingerprint.
- Completion binds the current stored claim and refuses expired leases before
  writes. One immediate transaction writes the normalized result, ordered cards,
  prerequisite UUIDs, source/index receipts, revisions and events. Broadcast is
  still after commit. DB failure rolls back the entire result and graph; interrupted
  inference is never replayed. No migration or native/provider change.
- The form says Create tasks and explains automatic draft creation. New completed
  requests show created status without per-card import buttons. Old requests,
  partial imports, source history and edited cards retain their previous semantics.
  A new consented analysis creates a separate graph; it does not infer semantic
  matching or replace existing tasks. Start remains unavailable.

Verification:
- `rtk mix test test/cuckoding/planning_test.exs test/cuckoding/planning_documents_test.exs test/cuckoding/team_assignments_test.exs test/cuckoding/specifications_test.exs test/cuckoding_web/planning_live_test.exs`: 39 passed.
- `rtk mix quality`: 196 tests passed; formatting, warning-free compile, Credo,
  Sobelow and mix_audit completed. Existing Sobelow quoted-keyword warnings remain.
- `rtk proxy bin/dev.build`: rebuilt Cuckoding.app. Hex continues to flag the
  existing Decimal 3.1.1 advisory EEF-CVE-2026-97853 / GHSA-6c27-994x-c52f despite
  mix_audit's clean result. Native-library relocation warnings are followed by
  signing. This is not a clean dependency-security claim.
- `rtk proxy bin/smoke`: packaged launch, authenticated routes, bootstrap/session,
  replay/origin refusal, heartbeat, graceful Quit and listener cleanup passed.
  Retained smoke root: `/private/tmp/ccoding-smoke.OtFXHu`.
- `rtk proxy env MIX_ENV=test mix run --no-start /private/tmp/cuckoding-r040m-proof/qa/seed.exs`:
  one synthetic persistence fixture passed using the actual contexts in an isolated
  test-mode database. It created three linked cards, edited one, rejected duplicate
  completion and left an expired running request. No provider credentials or
  inference were used. Fixture logging was verbose; all content was synthetic.
- Native packaged launch of that root reconciled the expired request to interrupted
  with one attempt and no additional cards. A second native launch retained exact
  task/revision/command hashes. Browser confirmed three cards, saved revision 2,
  dependency names, Create tasks, completed status without import buttons and the
  interrupted/no-replay explanation. Existing source rendering and expired-session
  behavior also pass LiveView regression checks.
- `rtk git diff --check` and local Markdown-link validation passed.

Build/data evidence:
- Private proof root `/private/tmp/cuckoding-r040m-proof` retains a verified SQLite
  backup, before/after durable-table hashes and PID/start/executable identities.
  Stopped only the verified prior app before replacing its bundle. QA used a separate
  root; its two instances and tabs were stopped/closed after verification.
- Relaunched the saved user root `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data`.
  All 11 durable setup/domain tables match the backup; sessions/auth events are
  excluded from that comparison. Integrity and foreign keys pass. The saved launcher
  and profile directories were not changed.
- Current observed native shell 87549, BEAM 87552, loopback port 49631. Browser
  confirmed Codex's one selected model, Cursor's seven, Team revision 2/Add role,
  and both saved Arenas. Catalogs are stale and require explicit refresh before
  new planning. These PIDs/port are observations, not permanent addresses.
- Screenshots and fixture IDs/hash comparisons are in `qa/` under the proof root.

Integration: local main from `feature/R040m-automatic-task-cards`; merged feature
branch removed. No push/deploy. Next: R020 provider execution grants/conformance,
then R050d/e bounded Start and the work/review loop.

Not exercised: real provider inference, physical sleep/wake, new native chooser,
narrow-screen visual QA, clean-machine/notarized release or battle execution.
Rust/site sources were unchanged, so their suites were not repeated. Fixture
success does not close real-account or execution acceptance.
