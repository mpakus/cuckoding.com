# R080i — Board progress and setup/planning activity

Claimed 2026-10-21 on `feature/r080i-board-activity`, starting from `95fa633`.
Only unrelated dirty file is the user's `Untitled.md.age`; left untouched.

Apply Ponytail full 5.3.2 (MIT), local observability/LiveView/quality guidance.
Reuse `Dashboard`, the existing board panel and guarded LiveComponents; no new
runtime permissions, migration, dependency or execution entry point.

`rtk proxy` is used for exact source/test/build and process-protocol output where
filtering would hide evidence. This slice uses read-only retained SQLite facts;
it cannot establish live provider cleanup or completion authority.

Delivered public fixed-kind setup/planning/repository records alongside battle
workers, sorted by saved queue time and capped at 20 (21-row lookahead per source).
Named connection labels are joined without exposing profiles/payloads; legacy
Codex is recognized only by its existing missing-ID command convention. Exact
Arena/Tabula scope refuses invalid/foreign pairs. The compact Board activity
disclosure reuses those rows and the selected board's frozen-task counts/current
saved team, with batched name lookup. Current assignments and battle bindings stay
distinct. No second Start, provider control or team adoption was introduced.

Verification so far:
- Three new domain checks failed before implementation. Focused domain/LiveView/
  board tests passed (23). Fixture setup/planning inputs and login URL canaries
  stay out of the new observations; reconnect and completed-work removal checked.
- Scope mutation (`board.id != tabula_id`) failed three focused regressions with
  exit 2; correct source restored before final verification.
- `node --test test/dialog_test.mjs test/agent_login_test.mjs
  test/activity_follow_test.mjs`: five passed; no JS changes.
- Source preview used the existing separate `.ccoding/ui-dev` data after read-only
  confirmation of no active commands/battles. CUA observed the global empty state,
  direct board navigation, Board activity/team, Return disclosure toggle and
  visible keyboard focus. Actual viewport widths 320/768/1024/1440 were selected;
  320/768 and wide disclosure text were readable. Height remained 252 under the
  docked inspector; this is not full responsive/zoom/screen-reader acceptance.
  A coordinate misclick briefly searched the literal number 320, then immediately
  returned to the local page; unrelated search-page issues are not app evidence.
  The local console showed extension messages; a complete Issues/axe audit was
  not performed. No provider invoked, fixture injected or team/draft saved.
- Closed only the preview tab. Source launcher PID/start/executable/cwd/exclusive
  shell lock were verified; an integrity/FK-checked private DB backup was retained
  before audit-token SIGTERM to the launcher. Its authenticated shell shutdown
  exited cleanly and closed port 49793. A first executable comparison refused
  before effects because macOS runs framework Python via its Python.app wrapper;
  exact observed wrapper/start identity was then verified. Backup:
  `.ccoding/r080i-validation/before-ui-stop-ec07eed8-4ab5-4308-ba85-1e6151bab286.db`.

The first packaged build passed but current Hex metadata newly flagged Bandit
1.12.5 advisories EEF-CVE-2026-105659/105660. The local audit source had not flagged
them. Keep the release gate open and handle the dependency in its own next slice.
No native source changed; the prior R020r native suite is historical evidence,
not a rerun for this read-only UI slice. Real-provider work, sleep, notarization
and ten-minute first-user acceptance remain open.

Final verification after batched team lookup: `rtk proxy mix quality` exited 0,
431 tests passed; format/compile/Credo/Sobelow/local audit passed. Existing
lockfile keyword warnings remain. Production warnings-as-errors compilation,
`bin/dev.build` (strict/deep ad-hoc signature), changed-doc link targets and
`git diff --check` passed. `bin/smoke` passed authenticated routes, origin/replay
refusal, heartbeat, graceful quit and listener cleanup; data retained at
`/private/tmp/ccoding-smoke.XNKm0H`. Packaged helper SHA-256:
`24c6d651830f7e83282dea7ce66d426ecbb4f36a9764bcbff4783ad5d7a879b3`.
Review confirmed fixed metadata allowlists, bounded queries, foreign-scope refusal,
no per-role render queries, escaped text and no authority changes. Local integration
only; the new Bandit advisories remain the next dependency slice.
