# 1019 — Shared provider sign-in and model selection

## Scope / acceptance

Reuse a compatible app-owned authorization when adding another named agent;
keep each agent's model and project role assignments independent. Persist model
through snapshots to actual stage requests. Preserve existing profiles/history,
fail closed on invalid references, never copy tokens or promise permanent login.
Claimed task 1019 on feature/1019-shared-login-models; icon.png is unrelated.

## Instructions and reference

Read required product/architecture/database/flow/security/execution docs. Used
Ponytail 4.10.0 full (MIT), architecture, adapter, security, LiveView, workflow,
quality-gates, accessibility, UX-writing and OpenAI Docs skills.
RTK proxy exceptions: exact instruction/source reads and streaming tool output.
Memory lookup found no relevant implementation guidance.

XERJ project search failed: no node at localhost:9200. Direct source fallback:
vibe-kanban pinned 735654971bd396aa97b65166955678e4c34f8bf8,
crates/executors/src/executors/codex.rs:14-46, Apache-2.0. Home identity is
separate from model/launch config; no code copied, no personal-home fallback.
Official https://learn.chatgpt.com/docs/auth and
https://developers.openai.com/api/docs/guides/latest-model inspected for cached
login and Astra's model ID. A suggested model is not proof of account access.

## Verification

- `rtk env -u CR_PAT mix format` — passed.
- `rtk env -u CR_PAT mix quality` — final seed 533407: 256 tests,
  10 properties, zero failures; format, unused dependencies, warnings-as-errors
  compilation, Credo (201 files, 3226 mods/functions), Sobelow and Hex audit passed.
- Earlier full attempt encountered the existing SQLite concurrent-writer property
  lock (seed 385282) and a new Credo complexity warning. Simplified authorization
  selection's explicit-new branch; isolated property rerun passed and two full
  reruns passed (784567 and 533407). No concurrency fix is claimed.
- Initial focused run exposed a test fixture missing rendered Codex config;
  corrected the fixture before the passing full runs.
- `rtk env -u CR_PAT mix assets.build` — passed (Tailwind and esbuild).
- `rtk git diff --check` — passed.

Regression checks cover shared login commands/probe/launch, independent model
requests after probe deduplication, revoked root propagation, incompatible and
immutable references, model/name updates retaining authorization status, planning
and workflow model snapshots, and no duplicate alias commands in both UIs.
The migration test upgrades a copy of the prior schema, verifies every prior
account value and checks foreign keys/integrity; no data backfill or profile move.

Development DB backed up through SQLite backup (proxy exception for the exact
backup/integrity checks) to ignored
`tmp/1019-before-migration-XNSZPb/development.db` (0600, containing directory 0700).
`rtk env -u CR_PAT mix ecto.migrate` applied 20260920170000. Before/after counts:
2 accounts, 2 projects, 2 boards, 25 tasks, 7 runs. Existing account columns match
the backup exactly; integrity_check ok and foreign_key_check empty.
No credentials read, copied or printed; existing profile files untouched.

Browser: `/settings/agents` verified at desktop width. Native model selector
offers default/Astra/custom; custom input appears, runtime changes reset model,
Claude-only helper visibility works. No real accounts created/edited by browser
verification; persistence and live shared status are covered by LiveView tests.
Viewport override did not take effect (still 1280px), so narrow-screen acceptance
is not claimed. Full keyboard/screen-reader acceptance remains unverified.
Browser logged two MutationObserver observe(non-Node) errors also seen during
prior work; no matching source in assets/js, origin unresolved, no clean-console
claim. No JavaScript changed. `/health` returned ok after migration.

Ponytail kept the design to a nullable reference on existing accounts, native
inputs and existing profile/runtime components, with no new dependency or secret
store. Security skills retained per-run permission config, immutable historical
bindings and fail-closed compatibility. Provider-controlled expiry and refresh
mean years-long login cannot be guaranteed; real authenticated refresh/concurrent
provider acceptance remains the explicit task 1018 release gate.
