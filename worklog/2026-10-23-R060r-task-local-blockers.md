# R060r — Task-local attention and independent work

Implemented, verified and packaged; local integration pending. Branch
`feature/R060r-task-local-blockers`, base `c4f43f6`.
Ponytail full 5.3.2 MIT; workflow/OTP/LiveView, architecture, security and quality
guidance. No provider usage, personal profile, user workspace or publication.

Existing Waves records failed lanes but closes every admission until manual
decisions/backoff. Implement D052 as a new frozen policy: only validated settled
task blockers can permit independent continuation after a clean drain. Shared or
uncertain failures keep the Arena closed. Preserve all prior attempt/task facts,
criteria, budgets and ordinary one-Start flow. `Untitled.md.age` stays untouched.

## Implementation and review

New snapshots freeze `blocker_scope: task-local-continuation-v1`. TaskBlocks
retains only an exact validated provider `blocked` receipt or the exhausted task
Secutor changes-requested receipt, with verified cleanup. It rechecks immutable
snapshot/envelope/provider/session/candidate binding; descriptive UI metadata is
never the authority. Failed writers retain edits without capture/integration.

After all current workers drain, Battles can continue ready independent lanes
through the existing supervised runner, with exact bindings, current account
observations, original deadline and consumed counters. Waves excludes blocked
lanes, waits for integrated prerequisites and prioritizes shared failure attention.
No dependent advances, automatic Skip occurs or final review starts while any task
is unresolved. Explicit Skip retains omissions and requires reviewed Partial output.

Pause holds a clean task-block boundary for explicit Resume; a restart between
settled stages also pauses, and an interrupted claim still needs exact recovery
proof. Unknown/native/auth/transport/policy/timing/uncertain failures retain existing
Arena-wide closure/backoff rules. Multiple task blockers keep separate decisions.
The LiveView component uses one compact native disclosure and existing guarded
controls; it renders fixed reasons and frozen task titles, not raw provider data.

Migration eighteen adds a blocked-task claim trigger and protects older bundles
through the existing schema-version startup fence. Historical snapshots are
constructed at insertion in fixtures, never rewritten. The old Skip regression
keeps its historical behavior; new-policy tests verify the extended flow.
No new dependency, provider, native operation/grant, model/account fallback,
mandatory setup step or per-task approval.

Reviewed connected settlement, worker admission, wave activation/focus,
retry/skip/pause/resume/restart, public rendering and compatibility guards. Reused
the existing receipts, immutable events, task states, scopes and supervisor.

## Verification

- Initial regression failed on the missing frozen policy. Final `rtk mix quality`
  (pinned Elixir/OTP PATH): **593 passed**, strict Credo (no issues), audits and
  Sobelow passed; terminal exit zero. Existing deliberate migration-module and
  audit quoted-keyword warnings remain. The first full run's four style/complexity
  findings were resolved without suppressions before final verification.
- **18** focused task-block cases include blocked/dependent/independent waves,
  retained writer edits, exhausted review, Pause/Resume, Stop, settled/interrupted
  restart, binding/turn-limit/foreign/uncertain refusal, separate Skip/Partial,
  transactional audit rollback and direct SQLite claim refusal. A real supervised
  runner test verifies separate worker PIDs, independent completion and a clean
  empty task supervisor; no provider was invoked.
  Review additionally caught the last blocked receipt losing a requested Pause
  and multiple Skip decisions releasing it; both are fixed and regression-tested.
- LiveView renders task-local progress and updates to Arena-wide attention on
  connection failure. Existing control/session and scope regressions pass in the
  full suite. No rendered-browser/screen-reader/timed human acceptance is claimed.
- Schema-seventeen migration fixture preserves all historical rows, integrity/FKs
  and its readable backup. Previous migration tests keep their exact target steps.
- Native build-manifest regression: **1 passed**. Native source and grants are
  unchanged; the prior full native/canary results were not relabeled as rerun.
- Removing the cleanup gate caused the targeted uncertain-cleanup regression to
  fail (15 passed, one failed). Exact source restored in `finally`; the restored
  focused suite passed, followed by the final full quality run including the
  writer and multiple-Pause cases. No mutated source was packaged.

Prior sealed R020s bundle and fresh schema-seventeen data were copied only into
`/private/tmp/cuckoding-r060r-prior-1jofvaz8` (0700). The source was the empty,
app-owned R020s smoke workspace, never a user profile. Backed up via VACUUM INTO
before the actual Ecto upgrade to eighteen; event facts/integrity/FKs preserved.
The retained older bundle intentionally refused the upgrade (exit one). Its private
crash slogan confirms the exact newer-schema error; raw dump was not printed.
Post-refusal schema eighteen and schema-seventeen backup are healthy, shell lock
released and no owned copied-bundle process remains. The old native helper's
generic smoke failure alone was not treated as proof of the refusal reason.

Private logs: `.ccoding/r060r-{red,focused,quality,quality-final,mutation,restored,
native-metadata,prior-upgrade,old-refusal}.log`. Local Markdown targets: **255**
verified before the final task/development links; whitespace clean.

## Final artifact

`rtk proxy bin/dev.build` passed after the final Pause fixes. Strict/deep sealed
local-preview receipt **fb96774c-b7cc-455c-a6cc-6b5578eed0dd**, schema eighteen,
source `c4f43f6` plus then-uncommitted application inputs. Source digest
`78b45f417decb897da5a6b2e236ed0b4df50233655bc57154541d26a613ecd1a`;
helper `e781983d69e3cbaaea3e7cdff174ccec36b1204eea78b5bd1cbdd7d9965b1c33`;
resource manifest `6801b4617f6c10b5a9e4c89f1245730a272144a368e6f813ed7fd7ecef4c5638`.
Earlier artifact `ad4552f1-d1df-4455-9d10-53c9ab6d1c0d` was superseded after
review; only the final receipt above describes the delivered local preview.

`rtk proxy bin/smoke` passed on fresh `/private/tmp/ccoding-smoke.wC4HlA`:
bundled launch/bootstrap, browser cookie, handoff replay/origin refusal,
heartbeat, graceful quit and listener cleanup. Schema eighteen, SQLite integrity/
FKs, released lock and exact application input digest verified after quit.

The final bundle also passed the same smoke on the disposable upgraded data at
`/private/tmp/cuckoding-r060r-prior-1jofvaz8/data`. All preexisting rows in nine fact
tables remain identical. The four expected shell/browser authorization, power
observation and quit audit events append normally. An initial overly strict
whole-events equality check was corrected to verify every prior immutable row
and inspect only appended public event kinds, without suppressing real changes.
Schema-seventeen backup remains readable; upgraded integrity/FKs and released
lock verified. No owned bundle/release process remains.

Final local Markdown targets: **267** verified; whitespace and the final artifact's
application input digest match. Final private logs: `.ccoding/r060r-quality-final.log`, `r060r-focused-final.log`,
`r060r-build-final.log`, `r060r-smoke-final.log`, `r060r-upgraded-smoke.log`.
No user workspace/profile was migrated, copied or started. Local integration pending.

Real-provider local-block/parallel/battle acceptance, general subprocess toolchains,
broader recovery and physical sleep, remaining providers, human accessibility/
ten-minute acceptance and signed clean-machine release remain open. No inference,
user data migration, push or publication.
