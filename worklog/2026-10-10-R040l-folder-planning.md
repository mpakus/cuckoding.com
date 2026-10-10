# R040l · Folder planning sources

Starting point: clean main at 62edc0a, eight commits ahead of origin/main.
Claim: R040l. Acceptance is in [task](../tasks/R040l-folder-planning.md).

Ponytail full 5.1.0 (MIT), workflow-and-kanban, elixir-phoenix-liveview,
security-review and quality-gates apply. Scope: existing document command/native
reader, planning contract, planning component, focused tests and affected docs.
Reuse the ledger, cancellation/session guards and pinned-descriptor read helper.
No agent/team changes, schema migration, provider grant or automatic execution.
`rtk proxy` is used for exact source, generated edits, protocol/build output and
read-only process/database evidence. The current user app remains untouched until
verified replacement; stop it before rebuilding its bundle.

Policy: `folder-documents-v1`, docs-first sorted traversal, at most 2,000 entries,
six directory levels, 16 source files, 16 KiB each / 64 KiB total. Do not truncate
file contents. Exclude hidden/generated/known credential paths; reject links,
hardlinks, special files and invalid text. Display skipped counts and limits.
Snapshots remain private until separate provider consent. New `brief-plan-v3`
supports up to 16 cited snapshots; retain v1/v2 validation/history.

Implementation:
- Reused `arena_git/initial.rs:55` (`open_at`) and `:79` (`read_at`) from
  repository revision `62edc0a`; no external implementation or dependency added.
- `PlanningDocuments.scan/3` uses the existing `preview_documents` command,
  transactional events, expiring claim and cancellation. Scoped selection and
  completion distinguish folder policy from manual path receipts.
- `brief-plan-v3` freezes exact source text on bounded stdin, retains earlier
  contracts and the same scratch/no-tools grant. Optional briefs require nonempty
  fresh source snapshots. Every citation is checked against the frozen request.
- Planning UI exposes one local read, useful empty/partial results and optional
  manual selection. Provider consent remains separate. A browser check caught a
  stale readiness message when no Speculator was connected; an explicit derived
  assign now makes LiveView refresh it. A focused regression covers that case.
- No migration; schema remains at nine versions. Agents, Team, saved role
  assignments and user files are unchanged.

Verification (final results):
- `rtk mix test test/cuckoding/planning_documents_test.exs test/cuckoding/planning_test.exs test/cuckoding_web/planning_live_test.exs`: 24 passed before the final readiness regression.
- `rtk mix test test/cuckoding_web/planning_live_test.exs:154`: final readiness regression passed.
- `rtk mix quality`: 193 tests passed, format/compile, Credo, Sobelow and mix_audit
  completed. Sobelow emits existing quoted-keyword lockfile warnings.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`: 52 passed.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked folder_snapshot_limits_empty_folders_and_interruption_are_explicit`:
  passed after adding the depth-limit canary to that test.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`: passed.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`: passed.
- `rtk proxy bin/dev.build`: final bundle built. Hex still reports pre-existing
  Decimal 3.1.1 advisory EEF-CVE-2026-97853 / GHSA-6c27-994x-c52f, despite mix_audit's
  clean result. Dependency treatment remains separate; this is not a clean security
  advisory claim. Existing native library rewrite warnings are followed by signing.
- `rtk proxy bin/smoke`: final packaged launch, protected routes, bootstrap/session,
  replay/origin refusal, heartbeat, graceful Quit and listener cleanup passed.
  Final smoke root: `/private/tmp/ccoding-smoke.z8eoNO`.
- `rtk git diff --check` and a Python local Markdown-target check: passed.

Packaged/browser evidence:
- Backed up the actual saved user database using SQLite backup; integrity/foreign
  keys passed. Stopped only verified owned shell/BEAM PID+start identities before
  every bundle replacement. Temporary QA used a separate data root and synthetic
  files, without provider profiles. Native chooser automation timed out; cancelled
  it normally and seeded only the isolated test Arena/board offline. This is not
  evidence of a fresh native chooser completion.
- CUA Chrome verification clicked **Read project folder** and observed the real
  packaged helper completion: `docs/plan.md`, then `lib/example.ex`; exact bytes
  and hashes retained, two exclusions and one size-limit skip, no Git directory or
  `plan_tabula` command. Typed brief survived. Expanded source text, retained
  history after restart and ready-without-provider message were visually verified.
- Private test artifacts: `/private/tmp/cuckoding-r040l-proof/qa/result.json`,
  `qa/fixture.json`, `folder-preview.png`, `before.db`, `data-before.json`,
  `data-after.json` and `proof.json`. Initial fixture seed attempts rolled back
  on column-count errors; the successful seed is retained as `qa/seed.py`.
- Final saved workspace relaunched with its original data at
  `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data`; shell 5584, BEAM 5587,
  loopback port 53940 (observations, not permanent addresses). Browser verified
  Codex's one and Cursor's seven selected models, Team revision 2/Add role and both
  Arenas. All 11 durable setup/domain tables matched pre-restart row/hash snapshots;
  session tokens and auth audit events were intentionally excluded from that match.
- Temporary QA processes/listeners were stopped and its browser tabs closed.
  Current user app remains running; the existing test launcher keeps its data root.

Completion: R040l integrated into local main from `feature/R040l-folder-planning`;
merged feature branch removed. No push/deploy. Next is R040m atomic proposal-graph
import, then provider execution gates and R050d/e Start/work/review. No real provider
inference, physical sleep/wake, clean-machine/notarized release or autonomous battle
was exercised here; fixture model responses do not establish those acceptances.
